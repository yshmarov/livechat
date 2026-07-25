# frozen_string_literal: true

module Livechat
  # The inbox. Every action is gated by config.authorize_agent; any
  # authorized teammate can read and answer any thread — it's a shared line,
  # not an assignment queue.
  class ConversationsController < ApplicationController
    before_action :require_agent
    before_action :set_conversation, except: :index
    layout 'livechat/application'

    PER_PAGE = 50

    def index
      @status = Conversation::STATUSES.include?(params[:status]) ? params[:status] : 'open'
      @counts = Conversation.group(:status).count
      @offset = params[:offset].to_i.clamp(0, 1_000_000)

      scope = Conversation.where(status: @status).recent_first
      page = scope.offset(@offset).limit(PER_PAGE + 1).to_a
      @more = page.size > PER_PAGE
      @conversations = page.first(PER_PAGE)

      # Unread badges for the whole page in one query.
      @unread = Message.from_visitor.unread
                       .where(conversation_id: @conversations.map(&:id))
                       .group(:conversation_id).count
    end

    def show
      @messages = @conversation.messages.chronological.to_a
      @conversation.mark_read_for_agent!
    end

    # Polled by dashboard.js: has anything new arrived in this thread?
    def poll
      render json: { latest: @conversation.messages.maximum(:id).to_i,
                     status: @conversation.status }
    end

    def resolve
      @conversation.resolve_by!(current_agent_label)
      redirect_to conversation_path(@conversation)
    end

    def reopen
      @conversation.reopen_by!(current_agent_label)
      redirect_to conversation_path(@conversation)
    end

    private

    def set_conversation
      @conversation = Conversation.find(params[:id])
    end
  end
end
