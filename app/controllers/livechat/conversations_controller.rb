# frozen_string_literal: true

module Livechat
  # The inbox. Every action is gated by config.authorize_agent; any
  # authorized teammate can read and answer any thread — it's a shared line,
  # not an assignment queue.
  class ConversationsController < ApplicationController
    before_action :require_agent
    before_action :set_conversation, except: %i[index index_poll]
    layout 'livechat/application'

    PER_PAGE = 50

    def index
      @status = Conversation::STATUSES.include?(params[:status]) ? params[:status] : 'open'
      @query = params[:q].to_s.strip.presence
      @counts = Conversation.group(:status).count
      @offset = params[:offset].to_i.clamp(0, 1_000_000)

      scope = Conversation.where(status: @status).recent_first
      scope = search(scope, @query) if @query
      page = scope.offset(@offset).limit(PER_PAGE + 1).to_a
      @more = page.size > PER_PAGE
      @conversations = page.first(PER_PAGE)

      # Unread badges and participating agents for the whole page, one query each.
      ids = @conversations.map(&:id)
      @unread = Message.from_visitor.unread.where(conversation_id: ids)
                       .group(:conversation_id).count
      @agents = Message.from_agent.where(conversation_id: ids)
                       .distinct.pluck(:conversation_id, :agent_label)
                       .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    end

    # Polled by dashboard.js on the list page: a token that changes whenever
    # anything an agent can see there changes — new message, new thread,
    # resolve/reopen.
    def index_poll
      render json: { token: [Message.maximum(:id).to_i,
                             Conversation.count,
                             Conversation.where(status: 'open').count].join('-') }
    end

    def show
      @messages = @conversation.messages.chronological.to_a
      @conversation.mark_read_for_agent!
    end

    # Polled by dashboard.js on the open thread: returns messages newer than
    # ?after=<id> so they can be appended live — no reload, so an agent's
    # half-written reply is never lost. Marks the visitor's messages read,
    # since the agent is looking right at them.
    def poll
      messages = @conversation.messages.chronological
      messages = messages.after_id(params[:after]) if params[:after].present?
      messages = messages.to_a
      @conversation.mark_read_for_agent! if messages.any?(&:visitor?)

      render json: {
        status: @conversation.status,
        messages: messages.map { |message| thread_message_json(message) }
      }
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

    # The fields dashboard.js needs to render a message bubble, matching the
    # thread partial: system events carry a ready localized line; visitor and
    # agent messages carry a display name (for the author header) and body.
    def thread_message_json(message)
      if message.system?
        { id: message.id, author: 'system',
          text: t("livechat.events.#{message.event}", agent: message.agent_label,
                                                      default: "%{agent} #{message.event} the conversation"),
          at: message.created_at.to_fs(:short) }
      else
        { id: message.id, author: message.author_type,
          name: message.agent? ? message.agent_label : @conversation.display_name,
          body: message.body, at: message.created_at.to_fs(:short) }
      end
    end

    # Case-insensitive match on who the visitor is or anything anyone wrote.
    # LOWER(...) LIKE is deliberately plain SQL — portable across SQLite,
    # PostgreSQL and MySQL alike (feedback_engine's proven approach).
    def search(scope, query)
      q = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      scope.where(
        'LOWER(visitor_label) LIKE :q OR LOWER(visitor_email) LIKE :q OR id IN ' \
        "(SELECT conversation_id FROM #{Message.table_name} WHERE LOWER(body) LIKE :q)",
        q: q
      )
    end
  end
end
