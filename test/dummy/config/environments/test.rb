# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
  config.action_mailer.delivery_method = :test
  # Not the default :async adapter. Attaching a file enqueues Active Storage's
  # analysis job, and :async runs it on a background thread that checks out its
  # own connection — writes that no test transaction covers, landing in the
  # middle of whatever runs next. That is where an order-dependent failure in a
  # test that never created a row comes from. Nothing here needs a job to run.
  config.active_job.queue_adapter = :test
  config.action_mailer.default_url_options = { host: "dummy.example.com" }
  # In-process store so the rate limiter has a working counter in tests.
  config.cache_store = :memory_store
end
