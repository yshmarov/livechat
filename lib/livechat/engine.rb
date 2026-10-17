# frozen_string_literal: true

module Livechat
  class Engine < ::Rails::Engine
    initializer 'livechat.ractor_middleware' do |app|
      app.middleware.insert_before 0, RactorSupport::Middleware
    end

    isolate_namespace Livechat

    initializer 'livechat.ractorize', before: 'action_controller.ractorize' do
      if Rails::Application.method_defined?(:ractorize!)
        Engine.routes.singleton_class.prepend(RactorSupport::MountedRoutes)
      end
      ActiveSupport.on_load(:before_ractorize) { Livechat::RactorSupport.prepare! }
    end

    rake_tasks do
      load File.expand_path('../tasks/livechat_tasks.rake', __dir__)
    end

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
