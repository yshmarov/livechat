# frozen_string_literal: true

module Livechat
  # Root of the AGENT surface: the inbox and agent replies.
  #
  # Inherits from `config.base_controller_class` — by default a plain
  # ActionController::Base, which is why `authorize_agent` exists. Point it at
  # the controller your own admin already inherits from and the inbox picks up
  # that stack wholesale: your layout, your helpers, your authentication, and
  # whatever request context your before_actions establish.
  #
  # Only the inbox hangs off it. The widget's endpoints stay on
  # ApplicationController, so wiring an admin base controller here can never
  # demand a staff session from a visitor starting a chat.
  class DashboardController < Livechat.base_controller
    include RequestContext

    # A host base controller brings its own layout, and declaring one here would
    # override it. So the gem only claims the layout when it owns the decision:
    # no host base controller, or a host that named an `agent_layout` explicitly.
    layout :livechat_agent_layout unless superclass != ActionController::Base &&
                                         Livechat.config.agent_layout == Configuration::DEFAULT_AGENT_LAYOUT

    before_action :require_agent

    # A host base controller has configured CSRF already; declaring it twice
    # would run the check twice.
    protect_from_forgery with: :exception if superclass == ActionController::Base
  end
end
