# frozen_string_literal: true

module Livechat
  # The widget's API. Every action is scoped to the requesting visitor — the
  # signed-in user's id, or the guest cookie token — so there is nothing to
  # enumerate and no id to leak. Gated by config.enabled and rate-limited.
  class VisitorController < ApplicationController
    before_action :require_enabled
    before_action :claim_guest_conversations

    if respond_to?(:rate_limit) && Livechat.config.rate_limit
      rate_limit(**Livechat.config.rate_limit,
                 only: %i[create email],
                 with: -> { render_rate_limited })
    end

    # GET widget/conversation(?after=<id>) — the widget's single source of
    # truth: thread status, unread count for the launcher badge, and messages
    # (all of them, or only those after the given id when polling).
    def show
      conversation = find_conversation
      return render json: empty_state unless conversation

      messages = conversation.messages.chronological
      messages = messages.after_id(params[:after]) if params[:after].present?

      render json: {
        status: conversation.status,
        unread: conversation.messages.from_agent.unread.count,
        email: conversation.visitor_email.present?,
        cable: cable_payload(conversation),
        typing: conversation.typing?('agent'),
        messages: messages.map(&:as_widget_json)
      }
    end

    # POST widget/messages — first message starts the thread; writing into a
    # resolved thread reopens it.
    def create
      message = nil
      # One transaction, so an invalid first message never leaves an empty
      # conversation behind.
      ActiveRecord::Base.transaction do
        conversation = find_conversation || start_conversation
        message = conversation.post_visitor_message!(params[:body].to_s.strip, files: params[:files])
      end
      refresh_context(message.conversation)
      Notifications.visitor_message(message)

      render json: { message: message.as_widget_json }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    # POST widget/email — a guest leaves an address so replies reach them
    # when they're gone.
    def email
      conversation = find_conversation
      return head :not_found unless conversation

      if conversation.update(visitor_email: params[:email].to_s.strip.presence)
        head :no_content
      else
        render json: { errors: conversation.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST widget/read — the visitor opened the panel and saw the replies.
    def read
      find_conversation&.mark_read_for_visitor!
      head :no_content
    end

    # POST widget/typing — a short-lived hint for agents who are watching the
    # inbox. It never starts a thread by itself; only real messages do that.
    def typing
      find_conversation&.typing!('visitor')
      head :no_content
    end

    private

    def find_conversation
      Conversation.for_visitor(visitor_id: current_visitor_id, visitor_token: visitor_token)
    end

    def start_conversation
      Conversation.create!(
        visitor_id: current_visitor_id,
        visitor_token: current_visitor_id ? visitor_token : ensure_visitor_token,
        visitor_label: visitor_label,
        visitor_email: (current_visitor.try(:email).presence if current_visitor),
        page_url: params[:page_url].to_s.first(255).presence,
        locale: params[:locale].to_s.first(10).presence
      )
    end

    def visitor_label
      return unless current_visitor

      Livechat.config.visitor_label.call(current_visitor).presence
    end

    # page_url and locale track the visitor's LAST message, not the first —
    # "where are they stuck right now" is what an answering agent needs.
    def refresh_context(conversation)
      updates = {}
      updates[:page_url] = params[:page_url].to_s.first(255) if params[:page_url].present?
      updates[:locale] = params[:locale].to_s.first(10) if params[:locale].present?
      conversation.update_columns(updates) if updates.any?
    end

    def empty_state
      { status: nil, unread: 0, email: false, cable: nil, typing: false, messages: [] }
    end

    # The signed stream token and cable URL the widget subscribes with, or nil
    # when push is off. The token is scoped to this conversation and only
    # reaches a visitor who already passed the gate to read it.
    def cable_payload(conversation)
      return unless Livechat.action_cable_enabled?

      { url: Livechat.config.action_cable_url,
        stream: Livechat.sign_stream("livechat:conversation:#{conversation.id}") }
    end
  end
end
