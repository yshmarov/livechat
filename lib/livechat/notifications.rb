# frozen_string_literal: true

module Livechat
  # Fires the host hooks and the built-in emails after a message is saved.
  # Email goes out only at the start of an unread stretch — the first message
  # nobody has seen yet — so a burst of messages is one email, not ten.
  # A failing hook must never break the chat, so hooks are rescued and logged.
  module Notifications
    class << self
      def visitor_message(message)
        run_hook { Livechat.config.on_visitor_message.call(message) }
        return unless Livechat.config.emails_enabled?
        return unless Livechat.config.agent_email_list.any?
        return unless first_unread?(message, message.conversation.messages.from_visitor)

        Mailer.new_visitor_message(message).deliver_later
      end

      def agent_message(message)
        run_hook { Livechat.config.on_agent_message.call(message) }
        return unless Livechat.config.emails_enabled?
        return if message.conversation.visitor_email.blank?
        return unless first_unread?(message, message.conversation.messages.from_agent)

        Mailer.new_agent_reply(message).deliver_later
      end

      private

      def first_unread?(message, side)
        side.unread.where(id: ...message.id).none?
      end

      def run_hook
        yield
      rescue StandardError => e
        Rails.logger.error("[livechat] notification hook failed: #{e.class}: #{e.message}")
      end
    end
  end
end
