# frozen_string_literal: true

require 'livechat/version'
require 'livechat/configuration'
require 'livechat/widget'
require 'livechat/notifications'
require 'livechat/seeds'
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

    # File attachments are on only when the host has Active Storage AND hasn't
    # switched them off. Guards every attachment path so the widget degrades
    # to text-only rather than erroring where Active Storage is absent.
    def attachments_enabled?
      config.attach_files && Message.attachments_supported?
    end

    # Realtime push is opt-in and needs Action Cable loaded. Off by default:
    # the widget and inbox poll, and only speed up when a host turns this on.
    def action_cable_enabled?
      config.action_cable && defined?(ActionCable) ? true : false
    end

    # Signs the Action Cable stream names handed to clients, so a subscriber
    # can only listen to a conversation the server already let it see — the
    # widget receives its stream token through the gated /conversation
    # endpoint, never guessing one. Same idea as Turbo's signed streams.
    def stream_verifier
      @stream_verifier ||= Rails.application.message_verifier('livechat/stream')
    end

    def sign_stream(name)
      stream_verifier.generate(name.to_s)
    end

    def verify_stream(token)
      stream_verifier.verify(token.to_s)
    rescue StandardError
      nil
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
