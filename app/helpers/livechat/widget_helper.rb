# frozen_string_literal: true

module Livechat
  # Included into the host's ActionView. Drop `<%= livechat_tag %>` before
  # </body> in your layout; it renders nothing unless chat is enabled for the
  # request. The widget shows a floating launcher (unless show_launcher is
  # off) and also opens from any element carrying `data-livechat-open`, or
  # from `window.Livechat.open()`.
  module WidgetHelper
    def livechat_tag
      return unless Livechat.enabled?(request)

      Widget.snippet(
        locale: I18n.locale,
        authenticated: livechat_visitor.present?,
        nonce: (content_security_policy_nonce if respond_to?(:content_security_policy_nonce))
      ).html_safe
    end

    # A plain, unstyled <button> that opens the chat — it picks up the host's
    # own styles. Put it anywhere on a page that also renders livechat_tag.
    def livechat_button(label: nil, **)
      return unless Livechat.enabled?(request)

      label ||= I18n.t(:launcher, scope: :livechat, default: 'Chat with us')
      tag.button(label, type: 'button', 'data-livechat-open': '', **)
    end

    private

    def livechat_visitor
      return @livechat_visitor if defined?(@livechat_visitor)

      @livechat_visitor = Livechat.config.current_user.call(request)
    end
  end
end
