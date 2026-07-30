# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_cable/engine"
require "active_job/railtie"

require "livechat"

module Dummy
  class Application < Rails::Application
    # Pin the root to test/dummy; otherwise Rails walks up to the gem repo (it
    # has a Gemfile) and can't find config/database.yml.
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.1
    config.eager_load = false
    # The schema is defined inline by test_helper; there is no db/schema.rb.
    config.active_record.maintain_test_schema = false
    config.secret_key_base = "livechat-dummy-secret"
    config.i18n.available_locales = %i[en fr ar]
    config.i18n.default_locale = :en

    # Active Storage: an in-process disk service under tmp, so attachment
    # tests never reach out. The tables are defined inline by test_helper.
    config.active_storage.service = :test
    config.active_storage.service_configurations = {
      "test" => { "service" => "Disk", "root" => File.expand_path("../tmp/storage", __dir__) },
      "livechat_test" => { "service" => "Disk", "root" => File.expand_path("../tmp/livechat_storage", __dir__) }
    }

    # Action Cable: the test pub/sub adapter, so ActionCable::TestHelper's
    # assert_broadcasts works without a real backend.
    config.action_cable.cable = { "adapter" => "test" }
    config.action_cable.disable_request_forgery_protection = true

    # A nonce-based CSP, so tests can assert the widget script is nonced.
    config.content_security_policy do |policy|
      policy.script_src :self
    end
    config.content_security_policy_nonce_generator = ->(_request) { "testnonce" }
    config.content_security_policy_nonce_directives = %w[script-src]
  end
end
