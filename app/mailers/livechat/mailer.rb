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
      @chat_url = chat_url(@conversation)
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

    # Where the visitor continues: the chat page, on the origin they wrote
    # from. That origin is where their guest cookie lives — a marketing site
    # proxying the mount path is a different origin from the app's own host,
    # and a link to the app's host would open an empty chat there. A page of
    # the host's own (chat_path outside the mount) prefers the mailer host,
    # since only the mount path is proxied. Without the chat page, it is the
    # page they last wrote from, as before.
    #
    # A signed-in visitor keeps that last page when the target is the engine's
    # page: theirs is usually behind the host's login, which takes a
    # signed-out reader through sign-in and back to their thread. The engine's
    # page can't ask the host to sign anyone in, and would show them an empty
    # guest chat instead.
    def chat_url(conversation)
      path = Livechat.chat_path
      return conversation.page_url unless path
      return path if path.match?(%r{\Ahttps?://}i)
      if conversation.visitor_id.present? && conversation.page_url.present? &&
         path == Livechat.config.engine_chat_path
        return conversation.page_url
      end

      origins = [origin_of(conversation.page_url), mailer_origin]
      origins.reverse! unless path.start_with?(Livechat.config.engine_chat_path)
      origin = origins.compact.first
      return unless origin

      url = "#{origin}#{path}"
      locale = conversation.locale.presence
      return url unless locale

      separator = path.include?('?') ? '&' : '?'
      "#{url}#{separator}locale=#{URI.encode_www_form_component(locale)}"
    end

    def origin_of(url)
      uri = URI.parse(url.to_s)
      return unless uri.host && %w[http https].include?(uri.scheme)

      URI::Generic.build(scheme: uri.scheme, host: uri.host, port: uri.port == uri.default_port ? nil : uri.port).to_s
    rescue URI::InvalidURIError
      nil
    end

    def mailer_origin
      options = ActionMailer::Base.default_url_options.merge(default_url_options)
      return unless options[:host]

      ActionDispatch::Http::URL.full_url_for(options.slice(:host, :protocol, :port).merge(path: '')).chomp('/')
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
