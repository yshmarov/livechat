# frozen_string_literal: true

module Livechat
  module Seeds
    THREADS = [
      {
        visitor_token: 'livechat-demo-checkout',
        visitor_label: 'Demo Customer',
        visitor_email: 'customer@example.com',
        page_url: '/checkout',
        locale: 'en',
        status: 'open',
        messages: [
          {
            author_type: 'visitor',
            body: 'I am trying to finish checkout, but the payment button keeps spinning.',
            read_at: true
          },
          {
            author_type: 'agent',
            agent_id: 'livechat-demo-agent',
            agent_label: 'Demo Support',
            body: 'Thanks for the details. I am checking the payment logs now.',
            read_at: true
          },
          { author_type: 'visitor', body: 'The order number is #DEMO-1042.' }
        ]
      },
      {
        visitor_token: 'livechat-demo-resolved',
        visitor_label: 'Demo Admin',
        visitor_email: 'admin@example.com',
        page_url: '/settings/billing',
        locale: 'en',
        status: 'resolved',
        messages: [
          { author_type: 'visitor', body: 'Where can I download last month\'s invoice?' },
          {
            author_type: 'agent',
            agent_id: 'livechat-demo-agent',
            agent_label: 'Demo Support',
            body: 'Open Settings, then Billing, then click Download next to the invoice.',
            read_at: true
          },
          {
            author_type: 'system',
            agent_label: 'Demo Support',
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
