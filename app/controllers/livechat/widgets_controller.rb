# frozen_string_literal: true

module Livechat
  # Serves the widget JavaScript as a plain same-origin script. Same-origin
  # matters: under a `script-src 'self'` (or nonce-based) CSP, an external
  # script from the app's own host is always allowed — including when Turbo
  # Drive swaps the <body> and re-runs body scripts under the *original*
  # page's CSP header, where a freshly minted inline nonce would be refused.
  class WidgetsController < ApplicationController
    # These assets are static and carry no user data; without this, Rails'
    # cross-origin JavaScript guard refuses to serve it to a plain
    # <script src> request.
    skip_forgery_protection

    # The script URLs carry a content fingerprint (?v=<md5>), so stale code
    # is structurally impossible: new code means a new URL. The canonical
    # fingerprinted URL is immutable and gets long-lived caching; anything
    # else only ETag-revalidates.
    def show
      serve(Widget.javascript, Widget.fingerprint)
    end

    # Bootstraps the widget on a page this app does not render. Carries the
    # config the layout helper would have rendered, so an external page needs
    # one <script src> and nothing that has to keep up with this engine.
    #
    # Never cached: it reflects the current visitor and whatever copy the host
    # resolves per request. The heavy widget.js it pulls in stays immutable.
    def embed
      body = if Livechat.enabled?(request)
               I18n.with_locale(embed_locale) do
                 Widget.embed_javascript(locale: I18n.locale,
                                         authenticated: current_visitor.present?,
                                         settings: Livechat.settings_for(request))
               end
             else
               ''
             end

      response.headers['Cache-Control'] = 'no-store'
      render plain: body, content_type: 'text/javascript'
    end

    def dashboard
      serve(Widget.dashboard_javascript, Widget.dashboard_fingerprint, 'text/javascript')
    end

    def dashboard_stylesheet
      serve(Widget.dashboard_stylesheet, Widget.dashboard_stylesheet_fingerprint, 'text/css')
    end

    private

    # An embedding site carries its own language; it asks for the matching
    # copy with ?locale=. Anything the host does not actually have falls back
    # rather than raising.
    def embed_locale
      requested = params[:locale].to_s
      I18n.available_locales.map(&:to_s).include?(requested) ? requested : I18n.locale
    end

    def serve(source, fingerprint, content_type = 'text/javascript')
      expires_in 1.year, public: true if params[:v] == fingerprint
      return unless stale?(etag: [Livechat::VERSION, fingerprint])

      render plain: source, content_type: content_type
    end
  end
end
