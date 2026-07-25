# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "dummy.example.com" }
  # In-process store so the rate limiter has a working counter in tests.
  config.cache_store = :memory_store
end
