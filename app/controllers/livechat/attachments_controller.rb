# frozen_string_literal: true

module Livechat
  # Serves message attachments through the engine — never a public Active
  # Storage URL — so every download is gated the same way the rest of the
  # chat is: you get the file only if you can work the inbox, or you are the
  # visitor whose conversation it belongs to. Streamed inline (not redirected
  # to a signed blob URL), so no long-lived link ever escapes the gate.
  class AttachmentsController < ApplicationController
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

    # Images render inline (so the widget can show them in an <img>); anything
    # else downloads. nosniff keeps the browser from second-guessing the type
    # of a visitor-supplied file.
    def stream(blob)
      response.headers['X-Content-Type-Options'] = 'nosniff'
      inline = blob.content_type.to_s.start_with?('image/')
      send_data blob.download,
                filename: blob.filename.to_s,
                type: blob.content_type.presence || 'application/octet-stream',
                disposition: inline ? 'inline' : 'attachment'
    end
  end
end
