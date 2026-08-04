# frozen_string_literal: true

# Stands in for a host app's own admin base controller — the thing a real host
# points `config.base_controller_class` at.
class HostAdminBaseController < ActionController::Base
  layout 'host_admin'
end
