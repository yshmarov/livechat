# frozen_string_literal: true

module Livechat
  # Root of the engine's PUBLIC surface: widget.js, the visitor API and the
  # attachment proxy (which serves visitors as well as agents). These stay on a
  # plain ActionController::Base deliberately — a visitor starting a chat must
  # not be routed through a host's admin controller, which would demand a staff
  # session for the widget.
  #
  # The inbox's root is DashboardController, and that is where
  # `config.base_controller_class` applies.
  class ApplicationController < ActionController::Base
    include RequestContext

    protect_from_forgery with: :exception

    private

    # A page on an allowlisted embed origin is static and has no Rails session
    # to mint a token from, so the Origin header stands in for one. Only this
    # controller's descendants are affected — the inbox verifies as usual.
    def verified_request?
      Livechat.embedded?(request) || super
    end
  end
end
