# frozen_string_literal: true

module Livechat
  # One thread per visitor — like a phone line, not a ticket queue. A visitor
  # writing into a resolved conversation reopens it; history stays in place.
  # Visitor identity is loose (no foreign key to the host's user table):
  # signed-in visitors are keyed by visitor_id, guests by a cookie token.
  class Conversation < ApplicationRecord
    STATUSES = %w[open resolved].freeze
    TYPING_TTL = 8.seconds

    has_many :messages, dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates :visitor_email, length: { maximum: 254 },
                              format: { with: URI::MailTo::EMAIL_REGEXP },
                              allow_blank: true
    validate :some_visitor_identity

    scope :recent_first, -> { order(last_activity_at: :desc, id: :desc) }

    STATUSES.each do |status|
      define_method(:"#{status}?") { self.status == status }
    end

    # The visitor's ongoing thread. Signed-in identity wins; guests are found
    # by their cookie token (only unclaimed threads — a token that has been
    # adopted by a user belongs to that user now).
    def self.for_visitor(visitor_id: nil, visitor_token: nil)
      if visitor_id.present?
        where(visitor_id: visitor_id.to_s).order(id: :desc).first
      elsif visitor_token.present?
        where(visitor_token: visitor_token, visitor_id: nil).order(id: :desc).first
      end
    end

    # A guest who signs in keeps their conversation: threads started under
    # the cookie token are adopted by the user, once, permanently.
    def self.claim!(visitor_token:, visitor_id:, visitor_label: nil)
      return if visitor_token.blank? || visitor_id.blank?

      where(visitor_token: visitor_token, visitor_id: nil)
        .update_all(visitor_id: visitor_id.to_s, visitor_label: visitor_label)
    end

    def post_visitor_message!(body, files: nil)
      transaction do
        update!(status: 'open') if resolved?
        message = messages.new(author_type: 'visitor', body: body)
        attach(message, files)
        message.save!
        clear_typing!('visitor')
        message
      end
    end

    def post_agent_message!(body:, agent_id:, agent_label:, files: nil)
      message = messages.new(author_type: 'agent', body: body,
                             agent_id: agent_id.to_s, agent_label: agent_label)
      attach(message, files)
      message.save!
      clear_typing!('agent')
      message
    end

    def resolve_by!(agent_label)
      return if resolved?

      transaction do
        update!(status: 'resolved')
        messages.create!(author_type: 'system', event: 'resolved', agent_label: agent_label)
      end
    end

    def reopen_by!(agent_label)
      return if open?

      transaction do
        update!(status: 'open')
        messages.create!(author_type: 'system', event: 'reopened', agent_label: agent_label)
      end
    end

    # Denormalized inbox-list fields, refreshed on every message. Written
    # with update_columns: cheap, no callbacks, no updated_at churn.
    def register_message(message)
      updates = { last_activity_at: message.created_at }
      updates[:last_message_preview] = message.preview unless message.system?
      update_columns(updates)
    end

    def unread_from_visitor_count = messages.from_visitor.unread.count

    def mark_read_for_agent!
      messages.from_visitor.unread.update_all(read_at: Time.current)
    end

    def mark_read_for_visitor!
      messages.from_agent.unread.update_all(read_at: Time.current)
    end

    def display_name
      visitor_label.presence || visitor_email.presence || "Visitor ##{id}"
    end

    def typing!(author_type)
      Rails.cache.write(typing_cache_key(author_type), true, expires_in: TYPING_TTL)
    end

    def typing?(author_type)
      Rails.cache.exist?(typing_cache_key(author_type))
    end

    def clear_typing!(author_type)
      Rails.cache.delete(typing_cache_key(author_type))
    end

    private

    # Attach only real uploads, and only where attachments are enabled — a
    # host without Active Storage (or with attachments off) drops the files
    # silently and the text message still goes through.
    def attach(message, files)
      return unless Livechat.attachments_enabled?

      uploads = Array(files).select { |file| file.respond_to?(:read) }
      message.files.attach(uploads) if uploads.any?
    end

    # Every conversation belongs to someone — a signed-in user or at least a
    # guest cookie. An unattributable thread could never be shown to its
    # visitor again.
    def some_visitor_identity
      return if visitor_id.present? || visitor_token.present?

      errors.add(:base, 'needs a visitor_id or a visitor_token')
    end

    def typing_cache_key(author_type)
      "livechat/conversations/#{id}/typing/#{author_type}"
    end
  end
end
