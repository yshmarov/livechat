# frozen_string_literal: true

module Livechat
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    private

    def current_visitor
      return @current_visitor if defined?(@current_visitor)

      @current_visitor = Livechat.config.current_user.call(request)
    end

    def current_visitor_id
      current_visitor.respond_to?(:id) ? current_visitor.id.to_s : nil
    end

    def require_enabled
      head :forbidden unless Livechat.enabled?(request)
    end

    # Server-side gate for the inbox. Default: development only.
    def require_agent
      return if Livechat.agent?(request)

      render plain: 'Forbidden. Set Livechat.config.authorize_agent to grant access.',
             status: :forbidden
    end

    def render_rate_limited
      message = I18n.t('livechat.error_rate_limited',
                       default: 'Too many messages. Please wait a moment and try again.')
      render json: { errors: [message] }, status: :too_many_requests
    end

    # Guests get a permanent random token — their key to the conversation
    # across visits. Signed-in visitors are keyed by id and only need the
    # cookie to carry a guest history into their account.
    def visitor_token
      cookies[:livechat_vid]
    end

    def ensure_visitor_token
      visitor_token.presence || begin
        token = SecureRandom.base58(24)
        cookies.permanent[:livechat_vid] = { value: token, httponly: true, same_site: :lax }
        token
      end
    end

    # A guest who signed in keeps their thread: adopt cookie-token
    # conversations into the account, then the cookie no longer matters.
    def claim_guest_conversations
      return unless current_visitor_id && visitor_token

      Conversation.claim!(
        visitor_token: visitor_token,
        visitor_id: current_visitor_id,
        visitor_label: Livechat.config.visitor_label.call(current_visitor).presence
      )
    end
  end
end
