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

    belongs_to :conversation

    validates :author_type, inclusion: { in: AUTHOR_TYPES }
    validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }, unless: :system?
    validates :agent_id, presence: true, if: :agent?
    validates :event, presence: true, inclusion: { in: EVENTS }, if: :system?
    validates :event, absence: true, unless: :system?

    scope :chronological, -> { order(:id) }
    scope :after_id, ->(id) { where(id: (id.to_i + 1)..) }
    scope :from_visitor, -> { where(author_type: 'visitor') }
    scope :from_agent, -> { where(author_type: 'agent') }
    scope :unread, -> { where(read_at: nil) }

    after_create_commit { conversation.register_message(self) }

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

    def as_widget_json
      {
        id: id,
        author: author_type,
        label: public_label,
        body: system? ? nil : body,
        event: event,
        at: created_at.iso8601
      }
    end
  end
end
