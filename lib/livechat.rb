# frozen_string_literal: true

require 'livechat/version'
require 'livechat/configuration'
require 'livechat/widget'
require 'livechat/engine'

# Live chat for Rails. A floating widget lets visitors — signed-in or
# anonymous — message your team; your team answers from a built-in inbox at
# the mount path, every reply signed with its author. Conversations live in
# your own database. When nobody is around, visitors leave an email and the
# thread continues there. No third-party script, no separate service.
module Livechat
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # Can this request see the widget and write messages? Checked on the
    # server for every widget endpoint and by the helper before rendering.
    def enabled?(request)
      !!config.enabled.call(request)
    end

    # Can this request work the inbox? Checked by every inbox action.
    def agent?(request)
      !!config.authorize_agent.call(request)
    end

    def app_name
      config.app_name.presence || rails_app_name
    end

    # The public face of an agent message. Blank display names fall back to
    # a localized "Support", so visitors always see a sender.
    def display_name_for(agent_label)
      name = config.agent_display_name.call(agent_label).presence
      name || I18n.t(:team, scope: :livechat, default: 'Support')
    end

    private

    # The application's module name, verbatim ("EthicsPortal", "SupeRails") —
    # no inflection games. Set config.app_name for anything fancier.
    def rails_app_name
      Rails.application.class.module_parent_name
    rescue StandardError
      'this app'
    end
  end
end
