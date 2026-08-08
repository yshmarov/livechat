# frozen_string_literal: true

module Livechat
  module Seeds
    THREADS = [
      {
        visitor_token: 'livechat-demo-checkout',
        visitor_label: 'Demo visitor · reply to this thread',
        visitor_email: 'customer@example.com',
        page_url: '/checkout?demo=livechat',
        locale: 'en',
        status: 'open',
        messages: [
          {
            author_type: 'visitor',
            body: 'I installed Livechat. What should I test first?',
            read_at: true
          },
          {
            author_type: 'agent',
            agent_id: 'livechat-demo-agent',
            agent_label: 'Demo support guide',
            body: 'Open the chat widget in your app, send a message, then reply from this inbox. The page URL, ' \
                  'locale, and configured visitor identity stay attached to the conversation.',
            read_at: true
          },
          {
            author_type: 'visitor',
            body: 'This last message is intentionally unread. Reply from the composer to complete the ' \
                  'visitor-to-agent loop.'
          }
        ]
      },
      {
        visitor_token: 'livechat-demo-resolved',
        visitor_label: 'Demo admin · production checklist',
        visitor_email: 'admin@example.com',
        page_url: '/settings?demo=livechat',
        locale: 'en',
        status: 'resolved',
        messages: [
          { author_type: 'visitor', body: 'What must I configure before this chat goes to production?' },
          {
            author_type: 'agent',
            agent_id: 'livechat-demo-agent',
            agent_label: 'Demo support guide',
            body: 'Render livechat_tag in the layout, set authorize_admin so only staff can read the inbox, ' \
                  'and configure current_user when signed-in visitors should keep their identity across pages.',
            read_at: true
          },
          {
            author_type: 'system',
            agent_label: 'Demo support guide',
            event: 'resolved'
          }
        ]
      }
    ].freeze

    def self.load!
      THREADS.map do |attributes|
        conversation = Livechat::Conversation.find_or_initialize_by(
          visitor_token: attributes.fetch(:visitor_token),
          visitor_id: nil
        )
        conversation.assign_attributes(attributes.except(:messages))
        conversation.save!
        conversation.messages.destroy_all
        attributes.fetch(:messages).each do |message_attributes|
          conversation.messages.create!(message_attributes.merge(read_at_value(message_attributes)))
        end
        conversation.reload
      end
    end

    def self.read_at_value(attributes)
      attributes[:read_at] ? { read_at: Time.current } : {}
    end
    private_class_method :read_at_value
  end
end
