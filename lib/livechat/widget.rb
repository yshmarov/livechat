# frozen_string_literal: true

require 'json'
require 'digest'

module Livechat
  # Serves the self-contained browser widget. The JavaScript is plain ES (no
  # framework, no build step) and styles itself inline, so it drops into any
  # Rails app regardless of its CSS or JS setup. It lives under lib/ (not
  # app/assets/) so a host that runs an asset pipeline never ingests it.
  module Widget
    SOURCE = File.expand_path('widget.js', __dir__)
    DASHBOARD_SOURCE = File.expand_path('dashboard.js', __dir__)

    # Right-to-left scripts, so the chat renders mirrored for those locales.
    # Matched on the language subtag, so region variants ("ar-EG") count too.
    RTL_LANGUAGES = %w[ar arc ckb dv fa ha he ks ku ps sd ug ur yi].freeze

    class << self
      def javascript
        @javascript ||= File.read(SOURCE)
      end

      def dashboard_javascript
        @dashboard_javascript ||= File.read(DASHBOARD_SOURCE)
      end

      # Content fingerprints for cache-busting script URLs: a changed file is
      # a changed URL, so no browser can ever run stale widget code — Safari
      # has been caught ignoring must-revalidate on same-URL scripts.
      def fingerprint
        @fingerprint ||= Digest::MD5.hexdigest(javascript)
      end

      def dashboard_fingerprint
        @dashboard_fingerprint ||= Digest::MD5.hexdigest(dashboard_javascript)
      end

      # The two <script> tags the helper renders.
      #
      # The config rides in a `type="application/json"` block: it is *data*,
      # not code, so the browser never executes it and Turbo never tries to
      # re-run it on a soft visit — which means it needs no CSP nonce and the
      # widget can re-read the *current* page's config on every `turbo:load`.
      #
      # The code is a same-origin `src` script served by the engine — NOT
      # inlined. Under a nonce-based CSP, Turbo Drive body swaps re-run body
      # scripts against the *original* page's CSP header, so a fresh inline
      # nonce gets refused; a same-origin src is covered by `'self'` on every
      # visit. `nonce:` is still stamped for hosts whose script-src has no
      # 'self'; pass nil when the app has no nonce.
      def snippet(locale:, authenticated:, nonce: nil)
        json = config_json(locale:, authenticated:)
        nonce_attr = nonce ? %( nonce="#{nonce}") : ''
        src = "#{Livechat.config.mount_path.chomp('/')}/widget.js?v=#{fingerprint}"

        %(<script type="application/json" data-livechat-config>#{json}</script>) +
          %(<script src="#{src}" defer#{nonce_attr} data-livechat-widget></script>)
      end

      def config_json(locale:, authenticated:)
        config = Livechat.config
        payload = {
          endpoint: config.widget_endpoint,
          locale: locale.to_s,
          rtl: rtl?(locale),
          authenticated: authenticated ? true : false,
          launcher: config.show_launcher ? true : false,
          appName: Livechat.app_name,
          labels: labels
        }
        # Escape "</" so a value can't close the <script> block early.
        payload.to_json.gsub('</', '<\/')
      end

      private

      # Every user-facing string in the widget, resolved through Rails I18n so
      # the chat follows the app's current locale. Each lookup carries an
      # English default, so the widget stays fully worded even when a key is
      # missing for the active locale.
      def labels
        config = Livechat.config
        {
          launcher: config.launcher_label.presence || t(:launcher, 'Chat with us'),
          greeting: config.greeting.presence || t(:greeting, 'Hi! How can we help?'),
          replyTime: config.reply_time_text.presence ||
            t(:reply_time, 'We usually reply within a few hours.'),
          placeholder: t(:placeholder, 'Write a message…'),
          send: t(:send, 'Send'),
          close: t(:close, 'Close'),
          you: t(:you, 'You'),
          team: t(:team, 'Support'),
          emailPrompt: t(:email_prompt, 'Get a copy of our reply by email:'),
          emailPlaceholder: t(:email_placeholder, 'you@example.com'),
          emailSave: t(:email_save, 'Save'),
          emailSaved: t(:email_saved, 'We will also reply by email.'),
          eventResolved: t(:event_resolved, 'Conversation resolved'),
          eventReopened: t(:event_reopened, 'Conversation reopened'),
          errorSend: t(:error_send, 'Could not send. Please try again.'),
          unreadAria: t(:unread_aria, 'unread messages')
        }
      end

      def t(key, default, **args)
        I18n.t(key, scope: :livechat, default: default, **args)
      end

      def rtl?(locale)
        RTL_LANGUAGES.include?(locale.to_s.downcase.split(/[-_]/).first)
      end
    end
  end
end
