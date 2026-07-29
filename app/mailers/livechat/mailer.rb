# frozen_string_literal: true

module Livechat
  # The two built-in notification emails. Plain text, no branding — they are
  # nudges back into the conversation, not newsletters. Both require
  # config.mailer_from; the callers in Livechat::Notifications enforce the
  # rest of the conditions (recipients present, first unread message).
  class Mailer < ActionMailer::Base
    MAX_MESSAGES = 5

    # To the team: a visitor wrote and nobody has read it.
    def new_visitor_message(message)
      @message = message
      @conversation = message.conversation
      @inbox_url = inbox_url(@conversation)
      assign_unread_digest(message, @conversation.messages.from_visitor)

      mail from: Livechat.config.mailer_from,
           to: Livechat.config.agent_email_list,
           subject: I18n.t('livechat.mail.visitor_subject',
                           name: @conversation.display_name, app: Livechat.app_name,
                           default: '%{name} wrote to you on %{app}')
    end

    # To the visitor: an agent replied while they were away.
    def new_agent_reply(message)
      @message = message
      @conversation = message.conversation
      assign_unread_digest(message, @conversation.messages.from_agent)

      mail from: Livechat.config.mailer_from,
           to: @conversation.visitor_email,
           subject: I18n.t('livechat.mail.reply_subject',
                           name: message.public_label, app: Livechat.app_name,
                           default: '%{name} replied to you on %{app}')
    end

    private

    # An absolute link to the inbox needs a host. Reuse the one hosts already
    # configure for Action Mailer (Devise needs it too); without one, the
    # email simply carries no link.
    def inbox_url(conversation)
      host = default_url_options[:host] || ActionMailer::Base.default_url_options[:host]
      return unless host

      Livechat::Engine.routes.url_helpers.conversation_url(
        conversation, host: host, **default_url_options.except(:host),
                      script_name: Livechat.config.mount_path.chomp('/')
      )
    rescue StandardError
      nil
    end

    def assign_unread_digest(message, side)
      scope = side.unread.where(id: message.id..).chronological
      unread_count = scope.count
      @messages = scope.limit(MAX_MESSAGES).to_a
      @messages = [message] if @messages.empty?
      @message_count = [unread_count, @messages.size].max
      @more_count = [@message_count - @messages.size, 0].max
      @attachment_names = @messages.index_with { |digest_message| attachment_names(digest_message) }
    end

    def attachment_names(message)
      return [] unless message.files_attached?

      message.attached_files.map { |file| file.filename.to_s }
    end
  end
end
