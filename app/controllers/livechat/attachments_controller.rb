# frozen_string_literal: true

module Livechat
  # Serves message attachments through the engine — never a public Active
  # Storage URL — so every download is gated the same way the rest of the
  # chat is: you get the file only if you can work the inbox, or you are the
  # visitor whose conversation it belongs to. Streamed inline (not redirected
  # to a signed blob URL), so no long-lived link ever escapes the gate.
  class AttachmentsController < ApplicationController
    include ActiveStorage::Streaming if defined?(::ActiveStorage::Streaming)

    def show
      attachment = find_attachment
      return head :not_found unless attachment

      message = attachment.record
      return head :forbidden unless message.is_a?(Livechat::Message) &&
                                    authorized_for?(message.conversation)

      stream(attachment.blob)
    end

    private

    def find_attachment
      return unless Livechat.attachments_enabled?

      ActiveStorage::Attachment.find_by(id: params[:id], name: 'files',
                                        record_type: Livechat::Message.name)
    end

    def authorized_for?(conversation)
      return true if Livechat.agent?(request)
      return false unless Livechat.enabled?(request)

      owns_conversation?(conversation)
    end

    # Mirrors Conversation.for_visitor: a signed-in visitor owns their thread
    # by id; a guest owns an unclaimed thread carrying their cookie token.
    def owns_conversation?(conversation)
      if current_visitor_id
        conversation.visitor_id == current_visitor_id
      elsif visitor_token.present?
        conversation.visitor_id.nil? && conversation.visitor_token == visitor_token
      else
        false
      end
    end

    # Images and audio render inline (so the clients can show native media
    # controls); anything else downloads. Responses are private and never
    # stored, and byte ranges keep audio seek/playback working without handing
    # out an Active Storage service URL.
    def stream(blob)
      response.headers['X-Content-Type-Options'] = 'nosniff'
      response.headers['Cache-Control'] = 'private, no-store'
      disposition = inline?(blob) ? 'inline' : 'attachment'

      if request.headers['Range'].present?
        if inline_audio?(blob)
          send_audio_byte_range_data(blob, request.headers['Range'])
        else
          send_blob_byte_range_data(blob, request.headers['Range'], disposition:)
        end
      elsif inline_audio?(blob)
        stream_audio(blob)
      else
        response.headers['Accept-Ranges'] = 'bytes'
        response.headers['Content-Length'] = blob.byte_size.to_s
        send_blob_stream(blob, disposition:)
      end
    end

    # Active Storage deliberately forces types outside its image/PDF allowlist
    # to download. The widget's recorded voice notes are a small explicit
    # exception; nosniff plus an audio Content-Type keeps them media-only.
    def inline?(blob)
      AttachmentPolicy.inline?(blob.content_type)
    end

    def inline_audio?(blob)
      AttachmentPolicy.audio?(blob.content_type)
    end

    def stream_audio(blob)
      response.headers['Accept-Ranges'] = 'bytes'
      response.headers['Content-Length'] = blob.byte_size.to_s
      send_stream(filename: blob.filename.sanitized, disposition: 'inline', type: blob.content_type) do |stream|
        blob.download { |chunk| stream.write(chunk) }
      end
    rescue ActiveStorage::FileNotFoundError
      expires_now
      head :not_found
    end

    def send_audio_byte_range_data(blob, range_header)
      ranges = Rack::Utils.get_byte_ranges(range_header, blob.byte_size)
      range = ranges.first if ranges&.one?
      return head :range_not_satisfiable unless range
      return head :range_not_satisfiable if range.end - range.begin >= streaming_chunk_max_size

      data = blob.download_chunk(range)
      response.headers['Content-Range'] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"
      response.headers['Accept-Ranges'] = 'bytes'
      response.headers['Content-Length'] = data.bytesize.to_s
      send_data data, filename: blob.filename.sanitized, disposition: 'inline',
                      status: :partial_content, type: blob.content_type
    end

    # Rails 8 exposes this knob; Rails 7.1/7.2 do not. Match the newer default
    # on older supported releases so a Range header cannot force an unbounded
    # in-memory chunk.
    def streaming_chunk_max_size
      return ActiveStorage.streaming_chunk_max_size if ActiveStorage.respond_to?(:streaming_chunk_max_size)

      100 * 1024 * 1024
    end
  end
end
