# frozen_string_literal: true

module Livechat
  # Included into the host's ActionView. Kept under lib and required before the
  # engine registers its Action View load hook: a host initializer may load
  # Action View before Rails sets up application autoloaders, when a helper
  # living only under app/helpers is not yet a resolvable constant.
  module WidgetHelper
    def livechat_tag
      return unless Livechat.enabled?(request)

      Widget.snippet(
        locale: I18n.locale,
        authenticated: livechat_visitor.present?,
        settings: Livechat.settings_for(request),
        nonce: (content_security_policy_nonce if respond_to?(:content_security_policy_nonce))
      ).html_safe
    end

    # A plain, unstyled <button> that opens the chat — it picks up the host's
    # own styles. Pass message: to prefill the composer with page-specific
    # context. Put it anywhere on a page that also renders livechat_tag.
    def livechat_button(label = nil, message: nil, **options)
      return unless Livechat.enabled?(request)

      label ||= options.delete(:label)
      label ||= I18n.t(:launcher, scope: :livechat, default: 'Chat with us')
      data = (options.delete(:data) { {} } || {}).merge(livechat_open: '')
      data[:livechat_message] = message if message.present?

      tag.button(label, type: 'button', data:, **options)
    end

    # The chat itself, in your page instead of floating over it: the visitor's
    # own conversation, filling this element. Give it a height (or put it in a
    # container that has one). The bubble stays away while it is on the page.
    # Like livechat_button, it is only the element — livechat_tag in your
    # layout brings the widget that fills it.
    def livechat_chat(**options)
      return unless Livechat.enabled?(request)

      data = (options.delete(:data) { {} } || {}).merge(livechat_chat: '')
      tag.div(data:, **options)
    end

    private

    def livechat_visitor
      return @livechat_visitor if defined?(@livechat_visitor)

      @livechat_visitor = Livechat.config.current_user.call(request)
    end
  end
end
