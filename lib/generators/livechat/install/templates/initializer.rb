# frozen_string_literal: true

Livechat.configure do |config|
  # Shown in the widget header and in notification emails. Defaults to your
  # Rails application name.
  # config.app_name = "My App"

  # Who sees the widget and can write. Return false to hide and reject for
  # this request. Defaults to everyone.
  # config.enabled = ->(request) { true }

  # Who can answer at the mount path. Defaults to development only — override
  # before deploying.
  # config.authorize_agent = ->(request) { request.env["warden"]&.user&.admin? }

  # Resolve the current user (optional). Return an object responding to #id,
  # or nil. Signed-in visitors keep one conversation across devices; guests
  # are tracked with a cookie. The same user is the agent when replying.
  # config.current_user = ->(request) { request.env["warden"]&.user }

  # How visitors appear in the inbox.
  # config.visitor_label = ->(user) { user.name.presence || user.email }

  # How agents are attributed on their replies.
  # config.agent_label = ->(user) { user.name.presence || user.email }

  # What visitors see as the sender. Default: the agent_label unchanged.
  # Return a first name, or a constant to keep the team anonymous.
  # config.agent_display_name = ->(label) { label.split.first }

  # Widget copy. nil = localized defaults.
  # config.greeting = "Hi! How can we help?"
  # config.reply_time_text = "We usually reply within a few hours."
  # config.launcher_label = "Chat with us"

  # The floating bubble. Set false and open the widget from your own
  # elements carrying data-livechat-open, or window.Livechat.open().
  # config.show_launcher = true

  # Email the team when a visitor writes and nobody has read it — one email
  # per unread stretch, not one per message. Both settings are required.
  # config.mailer_from = "chat@example.com"
  # config.agent_emails = ["support@example.com"]
  # config.agent_emails = -> { User.where(admin: true).pluck(:email) }

  # Called with each saved Livechat::Message — notify Slack, push…
  # config.on_visitor_message = ->(message) {}
  # config.on_agent_message = ->(message) {}

  # Per-IP throttle for the widget endpoints (Rails 7.2+; ignored on 7.1).
  # config.rate_limit = { to: 30, within: 1.minute }

  # Keep in sync with the `mount` in config/routes.rb.
  # config.mount_path = "/livechat"
end
