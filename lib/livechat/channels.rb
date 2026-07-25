# frozen_string_literal: true

# Loaded from the engine only when Action Cable is present (see engine.rb), so
# a host without a cable never pays for it and never trips Zeitwerk eager-load
# on a missing ActionCable constant.
module Livechat
  # One channel for both sides of the chat. It carries no payload of its own —
  # a broadcast is a nudge ("something changed on this stream"); the client
  # then refetches through the same gated endpoint it already polls, so the
  # rendering, dedup and read-tracking logic stays in one place.
  #
  # Authorization IS the signature: the server only ever signs a stream name
  # it already let this subscriber see — the widget gets its conversation
  # stream from the gated /conversation endpoint, an agent gets conversation
  # and inbox streams from the (authorized) inbox pages. A subscriber that
  # can't present a validly signed livechat: stream is rejected.
  class StreamChannel < ActionCable::Channel::Base
    def subscribed
      stream = Livechat.verify_stream(params[:signed_stream])
      if stream&.start_with?('livechat:')
        stream_from stream
      else
        reject
      end
    end
  end
end
