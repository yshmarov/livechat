# frozen_string_literal: true

module Livechat
  class Engine < ::Rails::Engine
    isolate_namespace Livechat

    initializer 'livechat.helpers' do
      ActiveSupport.on_load(:action_view) do
        include Livechat::WidgetHelper
      end
    end

    # The channel lives under lib/ (not app/channels), required only where
    # Action Cable exists — so eager-load in an app without it never fails on
    # a missing ActionCable::Channel::Base.
    initializer 'livechat.action_cable' do
      require 'livechat/channels' if defined?(ActionCable)
    end

    initializer 'livechat.routing' do
      ActionDispatch::Routing::Mapper.include(Module.new do
        def mount_livechat(at: Livechat.config.mount_path, **options)
          Livechat.config.mount_path = at
          mount Livechat::Engine, at:, **options
        end
      end)
    end
  end
end
