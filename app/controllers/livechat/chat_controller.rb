# frozen_string_literal: true

module Livechat
  # GET <mount_path>/chat — the visitor's chat as a page of its own.
  #
  # Public, like the widget: it hangs off ApplicationController, never the
  # inbox's base controller. It names no conversation. The page carries the
  # widget in its inline mode, and the widget resolves the thread from the
  # signed-in id or guest cookie as it does everywhere else, so the URL is the
  # same for everyone and a leaked link shows a stranger only their own chat.
  #
  # Unlike the widget's endpoints this is an HTML page with a CSRF token, so
  # it needs the session and stays out of Livechat.public_paths.
  class ChatController < ApplicationController
    # Explicit, or Rails' implied lookup finds layouts/livechat/application —
    # the inbox's shell.
    layout false

    before_action :require_enabled

    def show
      return head :not_found unless Livechat.chat_path
      # A host that put the chat on a page of its own: send people there.
      if Livechat.chat_path != Livechat.config.engine_chat_path
        return redirect_to(Livechat.chat_path(locale: params[:locale].presence), allow_other_host: true)
      end

      I18n.with_locale(page_locale) { render :show }
    end

    private

    # This page doesn't run the host's locale switching, so a link carries the
    # visitor's language as ?locale= (the panel's icon and the reply email
    # both do). Anything the app doesn't have falls back.
    def page_locale
      requested = params[:locale].to_s
      I18n.available_locales.map(&:to_s).include?(requested) ? requested : I18n.locale
    end
  end
end
