# frozen_string_literal: true

module Livechat
  class Engine < ::Rails::Engine
    isolate_namespace Livechat

    initializer 'livechat.helpers' do
      ActiveSupport.on_load(:action_view) do
        include Livechat::WidgetHelper
      end
    end
  end
end
