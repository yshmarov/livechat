# frozen_string_literal: true

module Livechat
  class MessagesController < ApplicationController
    before_action :require_agent

    def create
      conversation = Conversation.find(params[:conversation_id])
      message = conversation.post_agent_message!(
        body: params[:body].to_s.strip,
        agent_id: current_agent_id,
        agent_label: current_agent_label,
        files: params[:files]
      )
      Notifications.agent_message(message)

      redirect_back fallback_location: conversation_path(conversation, anchor: "message-#{message.id}")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: conversation_path(conversation), alert: e.record.errors.full_messages.first
    end
  end
end
