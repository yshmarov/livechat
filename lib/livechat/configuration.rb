# frozen_string_literal: true

module Livechat
  # Host-tunable settings. Everything has a safe default, so a fresh install
  # works with zero configuration; the hooks below let an app decide who can
  # chat, who answers, and how everyone is named.
  class Configuration
    # The gem's own agent layout. Compared against, so DashboardController can
    # tell "the host left this alone" from "the host chose this".
    DEFAULT_AGENT_LAYOUT = 'livechat/application'

    # Shown in the widget header and in notification emails. nil resolves to
    # the Rails application name.
    attr_accessor :app_name

    # Per-request gate for the widget and its endpoints. Return false to hide
    # the widget and reject writes for this request.
    attr_accessor :enabled

    # Per-request gate for the inbox. Defaults to development only — override
    # it before deploying, e.g. with an admin check. Independent of `enabled`,
    # so your team can answer from production even where the widget is off.
    attr_accessor :authorize_agent

    # Layout used by the built-in inbox. Override this to render Livechat
    # inside your app's admin shell, e.g. "admin/application".
    attr_accessor :agent_layout

    # The controller the INBOX inherits from, as a String so it resolves lazily
    # rather than at config time. Default: a plain 'ActionController::Base',
    # where `authorize_agent` is the only gate.
    #
    # Name the controller your own admin already inherits from and the inbox
    # adopts that whole stack — layout, helpers, authentication, and any request
    # context your before_actions set up. `agent_layout` covers only the layout,
    # which leaves a host layout calling its own helpers to raise NameError under
    # the engine's isolated namespace.
    #
    # Only the inbox uses it. The widget's endpoints stay on the engine's own
    # public controller, so an admin base controller here can never demand a
    # staff session from a visitor starting a chat.
    attr_accessor :base_controller_class

    # Resolve the current user (optional). Return an object responding to
    # #id, or nil. Receives the request. Signed-in users keep one conversation
    # across devices; guests are tracked with a cookie.
    attr_accessor :current_user

    # Turn a resolved user into the visitor name shown in the inbox.
    attr_accessor :visitor_label

    # Turn a resolved user into the attribution stored on an agent's message.
    # Every reply carries this, so a thread with several teammates stays
    # legible.
    attr_accessor :agent_label

    # What visitors see as the sender of an agent message. Receives the
    # stored agent_label; return it unchanged (default), a first name, or a
    # constant like "Support team" to keep agents anonymous.
    attr_accessor :agent_display_name

    # Widget copy. nil uses the localized defaults. reply_time_text is the
    # honest line under the greeting — "We usually reply within a few hours."
    attr_accessor :greeting, :reply_time_text, :launcher_label

    # Optional customer-facing avatar shown in the widget header. Use a URL
    # string, or a callable receiving the request for tenant-specific branding.
    # nil keeps the text-only header.
    attr_accessor :avatar_url

    # Brand color for the widget (launcher, header, visitor bubbles, send
    # button) as a hex value, e.g. "#7c3aed". The widget picks black or white
    # text automatically for contrast. nil keeps the built-in blue.
    attr_accessor :accent_color

    # The floating launcher bubble. Set false to open the widget only from
    # your own elements carrying `data-livechat-open`.
    attr_accessor :show_launcher

    # Email addresses to notify when a visitor writes and nobody has read it —
    # an array, or a callable returning one. nil disables the built-in email.
    attr_accessor :agent_emails

    # From-address for the built-in notification emails. Required for any
    # email to be sent.
    attr_accessor :mailer_from

    # Called with each saved Livechat::Message — wire up Slack, Noticed,
    # push… Runs inline after save; keep it fast or hand off to a job.
    attr_accessor :on_visitor_message, :on_agent_message

    # Per-IP throttle for the public endpoints, as keyword arguments for
    # Rails' rate limiter (Rails 7.2+; ignored on 7.1). nil disables it.
    attr_accessor :rate_limit

    # Let visitors and agents attach files to messages. Requires Active
    # Storage in the host app (rails active_storage:install); silently
    # ignored when it isn't present, so the widget keeps working. Set false
    # to turn attachments off even where Active Storage exists.
    attr_accessor :attach_files

    # Named Active Storage service for chat attachments. nil uses the host
    # app's default service; set this to route files to a dedicated bucket,
    # folder, or provider-specific service entry.
    attr_accessor :storage_service

    # Cap on attachments per message, on the size of each file (bytes), and
    # an optional content-type allowlist (nil accepts any type). Enforced on
    # the server; a rejected upload comes back as a validation error.
    attr_accessor :max_attachments, :max_attachment_size, :allowed_attachment_types

    # Push new messages over Action Cable instead of waiting for the next
    # poll. Opt-in and off by default: polling stays the transport, so a
    # host that never mounts a cable keeps working; when on (and Action Cable
    # is present) a new message nudges the widget and the inbox to refresh at
    # once. Requires `/cable` mounted in the host's routes.
    attr_accessor :action_cable

    # Where the host mounts Action Cable. Only consulted when action_cable is
    # on. Keep in sync with the `mount ActionCable... => "/cable"` in routes.
    attr_accessor :action_cable_url

    # Where the engine is mounted. The widget calls paths under it, so keep
    # this in sync with the `mount` line in your routes.
    attr_accessor :mount_path

    def initialize
      @app_name = nil
      @enabled = ->(_request) { true }
      @authorize_agent = ->(_request) { Rails.env.development? }
      @agent_layout = DEFAULT_AGENT_LAYOUT
      @base_controller_class = 'ActionController::Base'
      @current_user = ->(_request) {}
      @visitor_label = ->(user) { user.try(:name).presence || user.try(:email).presence || user.to_s }
      @agent_label = ->(user) { user.try(:name).presence || user.try(:email).presence || user.to_s }
      @agent_display_name = ->(label) { label }
      @greeting = nil
      @reply_time_text = nil
      @launcher_label = nil
      @avatar_url = nil
      @accent_color = nil
      @show_launcher = true
      @agent_emails = nil
      @mailer_from = nil
      @on_visitor_message = ->(_message) {}
      @on_agent_message = ->(_message) {}
      @rate_limit = { to: 30, within: 60 }
      @mount_path = '/livechat'
      @attach_files = true
      @storage_service = nil
      @max_attachments = 5
      @max_attachment_size = 10 * 1024 * 1024
      @allowed_attachment_types = nil
      @action_cable = false
      @action_cable_url = '/cable'
    end

    def widget_endpoint = "#{mount_path.chomp('/')}/widget"

    def agent_email_list
      list = agent_emails
      list = list.call if list.respond_to?(:call)
      Array(list).compact_blank
    end

    def emails_enabled? = mailer_from.present?
  end
end
