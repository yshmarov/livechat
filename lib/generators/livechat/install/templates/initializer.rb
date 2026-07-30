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
  #
  # Devise / Warden:
  # config.current_user = ->(request) { request.env["warden"]&.user }
  #
  # Rails 8 built-in auth (bin/rails generate authentication):
  # config.current_user = lambda do |request|
  #   token = request.cookies["session_token"]
  #   Session.find_signed(token)&.user if token
  # end

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

  # Brand color (hex) for the launcher, header, bubbles and send button.
  # Text flips black/white automatically for contrast. nil = built-in blue.
  # config.accent_color = "#7c3aed"

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

  # File attachments. On by default, but only take effect where the app has
  # Active Storage (run `rails active_storage:install` once). Files are served
  # through the engine — gated the same as the chat — never a public blob URL.
  # config.attach_files = true
  # config.storage_service = nil # e.g. :livechat_uploads from config/storage.yml
  # config.max_attachments = 5
  # config.max_attachment_size = 10.megabytes
  # config.allowed_attachment_types = nil # e.g. %w[image/png image/jpeg application/pdf]

  # Realtime push over Action Cable. Off by default — the widget and inbox
  # poll, which needs nothing from your app. Turn this on to push new messages
  # the instant they arrive; polling stays the fallback. Requires Action Cable
  # mounted (the default `mount ActionCable... => "/cable"` in your routes).
  # config.action_cable = true
  # config.action_cable_url = "/cable"

  # Keep in sync with the `mount` in config/routes.rb.
  # config.mount_path = "/livechat"
end
