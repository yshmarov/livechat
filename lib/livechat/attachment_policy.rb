# frozen_string_literal: true

module Livechat
  # The small set of uploads the engine renders in a browser instead of
  # downloading. Active Storage owns the safe image/PDF allowlist; Livechat
  # adds common audio formats because voice messages are a first-class feature.
  module AttachmentPolicy
    INLINE_AUDIO_TYPES = %w[
      audio/mpeg audio/mp4 audio/ogg audio/wav audio/webm audio/x-wav
    ].freeze

    module_function

    def inline?(content_type)
      audio?(content_type) || ActiveStorage.content_types_allowed_inline.include?(content_type)
    end

    def image?(content_type)
      content_type.to_s.start_with?('image/') &&
        ActiveStorage.content_types_allowed_inline.include?(content_type)
    end

    def audio?(content_type)
      INLINE_AUDIO_TYPES.include?(content_type)
    end
  end
end
