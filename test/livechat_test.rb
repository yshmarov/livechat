# frozen_string_literal: true

require 'test_helper'

class LivechatTest < ActiveSupport::TestCase
  test 'mount_livechat keeps config.mount_path in sync with the route' do
    routes = ActionDispatch::Routing::RouteSet.new

    routes.draw do
      mount_livechat at: '/support'
    end

    assert_equal '/support', Livechat.config.mount_path
  end
end
