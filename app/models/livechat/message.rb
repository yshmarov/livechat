# frozen_string_literal: true

module Livechat
  # One chat entry. Three kinds of author: the visitor, a named agent, or the
  # system (resolve/reopen events, so a thread worked by several teammates
  # stays legible). Agent attribution is stored as loose fields — agent_id
  # plus a label resolved at write time — no foreign key to the host's users.
  class Message < ApplicationRecord
    AUTHOR_TYPES = %w[visitor agent system].freeze
    EVENTS = %w[resolved reopened].freeze
    MAX_BODY_LENGTH = 5_000

    # Attachments ride on Active Storage, which the host installs (it's a
    # standard Rails feature, not a livechat table). Where it isn't present
    # the association simply isn't declared and everything stays text-only.
    ATTACHMENTS_SUPPORTED = defined?(ActiveStorage) ? true : false
    def self.attachments_supported? = ATTACHMENTS_SUPPORTED

    belongs_to :conversation
    has_many_attached :files if ATTACHMENTS_SUPPORTED

    validates :author_type, inclusion: { in: AUTHOR_TYPES }
    validates :body, length: { maximum: MAX_BODY_LENGTH }, allow_blank: true
    validates :body, presence: true, unless: :body_optional?
    validates :agent_id, presence: true, if: :agent?
    validates :event, presence: true, inclusion: { in: EVENTS }, if: :system?
    validates :event, absence: true, unless: :system?
    validate :attachments_within_limits, if: :files_attached?

    scope :chronological, -> { order(:id) }
    scope :after_id, ->(id) { where(id: (id.to_i + 1)..) }
    scope :from_visitor, -> { where(author_type: 'visitor') }
    scope :from_agent, -> { where(author_type: 'agent') }
    scope :unread, -> { where(read_at: nil) }

    after_create_commit :on_created

    AUTHOR_TYPES.each do |type|
      define_method(:"#{type}?") { author_type == type }
    end

    def read? = read_at.present?

    # What the widget shows as the sender of an agent message — run through
    # config.agent_display_name, so hosts control how much of the team's
    # identity visitors see.
    def public_label
      agent? ? Livechat.display_name_for(agent_label) : nil
    end

    # The attached files, or an empty list where Active Storage is absent or
    # attachments are off — callers never have to branch on support.
    def attached_files
      files_attached? ? files : []
    end

    def files_attached?
      Livechat.attachments_enabled? && files.attached?
    end

    # A one-line summary for the inbox list: the body, or a note of what was
    # attached when a message is files-only.
    def preview
      return body.to_s.truncate(140) if body.present?
      return '' unless files_attached?

      names = files.map { |file| file.filename.to_s }
      names.one? ? "📎 #{names.first}" : "📎 #{names.size} files"
    end

    def as_widget_json
      {
        id: id,
        author: author_type,
        label: public_label,
        body: system? ? nil : body,
        event: event,
        attachments: attachments_json,
        at: created_at.iso8601
      }
    end

    # The shape the inbox renders — mirrors the thread partial. system events
    # carry a ready localized line; visitor and agent messages carry a display
    # name for the author header. Lives here (not in the controller) so an
    # Action Cable broadcast can build it without a request.
    def as_inbox_json(conversation = self.conversation)
      if system?
        { id: id, author: 'system',
          text: I18n.t("livechat.events.#{event}", agent: agent_label,
                                                   default: "%{agent} #{event} the conversation"),
          at: created_at.to_fs(:short) }
      else
        { id: id, author: author_type,
          name: agent? ? agent_label : conversation.display_name,
          body: body, attachments: attachments_json, at: created_at.to_fs(:short) }
      end
    end

    # [{ id:, name:, url:, image:, audio:, size: }] — url is the gated engine
    # route; image/audio flags tell clients which native preview to render.
    def attachments_json
      return [] unless files_attached?

      base = Livechat.config.mount_path.to_s.chomp('/')
      files.map do |file|
        content_type = file.content_type.to_s
        { id: file.id,
          name: file.filename.to_s,
          url: "#{base}/attachments/#{file.id}",
          image: content_type.start_with?('image/'),
          audio: content_type.start_with?('audio/'),
          size: file.byte_size }
      end
    end

    private

    # A visitor/agent message needs a body unless it carries a file instead —
    # an image with no caption is a perfectly good message. System messages
    # never have a body.
    def body_optional?
      system? || files_attached?
    end

    def attachments_within_limits
      config = Livechat.config
      if files.size > config.max_attachments
        errors.add(:base, I18n.t('livechat.attachments.too_many', count: config.max_attachments,
                                                                  default: 'Too many files (max %{count}).'))
      end

      files.each do |file|
        if file.byte_size > config.max_attachment_size
          errors.add(:base, I18n.t('livechat.attachments.too_large', name: file.filename,
                                                                     default: '%{name} is too large.'))
        end
        types = config.allowed_attachment_types
        next if types.blank? || types.include?(file.content_type)

        errors.add(:base, I18n.t('livechat.attachments.type_rejected', name: file.filename,
                                                                       default: "%{name}'s type isn't allowed."))
      end
    end

    def on_created
      conversation.register_message(self)
      broadcast_new_message
    end

    # Nudge — not the payload — so the client refetches through its normal,
    # authorized path and the rendering/dedup/read logic stays in one place.
    # Rescued: a chat must never break because a cable backend hiccuped.
    def broadcast_new_message
      return unless Livechat.action_cable_enabled?

      ActionCable.server.broadcast("livechat:conversation:#{conversation_id}", { nudge: id })
      ActionCable.server.broadcast('livechat:inbox', { nudge: id })
    rescue StandardError => e
      Rails.logger.error("[livechat] cable broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
