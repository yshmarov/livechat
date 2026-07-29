# frozen_string_literal: true

require 'test_helper'

class NotificationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test 'on_visitor_message hook fires with the saved message' do
    seen = []
    Livechat.config.on_visitor_message = ->(message) { seen << message }

    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json

    assert_equal 1, seen.size
    assert_equal 'hello', seen.first.body
  end

  test 'a failing hook never breaks the chat' do
    Livechat.config.on_visitor_message = ->(_message) { raise 'boom' }

    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    assert_response :created
  end

  test 'agents are emailed once per unread stretch' do
    Livechat.config.mailer_from = 'chat@example.com'
    Livechat.config.agent_emails = ['team@example.com']

    assert_enqueued_emails 1 do
      post '/livechat/widget/messages', params: { body: 'first' }, as: :json
      post '/livechat/widget/messages', params: { body: 'second' }, as: :json
    end

    # Once an agent reads the thread, the next message starts a new stretch.
    Livechat::Conversation.last.mark_read_for_agent!
    assert_enqueued_emails 1 do
      post '/livechat/widget/messages', params: { body: 'third' }, as: :json
    end
  end

  test 'no email without mailer_from or agent_emails' do
    Livechat.config.agent_emails = ['team@example.com'] # but no mailer_from
    assert_no_enqueued_emails do
      post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    end
  end

  test 'visitor mail content and recipients' do
    Livechat.config.mailer_from = 'chat@example.com'
    Livechat.config.agent_emails = -> { %w[a@example.com b@example.com] }

    post '/livechat/widget/messages',
         params: { body: 'help me', page_url: 'http://dummy.example.com/checkout', locale: 'en' },
         as: :json
    post '/livechat/widget/messages', params: { body: 'payment fails' }, as: :json

    assert_enqueued_emails 1
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal %w[a@example.com b@example.com], mail.to
    assert_includes mail.body.to_s, '2 unread messages'
    assert_includes mail.body.to_s, 'help me'
    assert_includes mail.body.to_s, 'payment fails'
    assert_includes mail.body.to_s, 'Page: http://dummy.example.com/checkout'
    assert_includes mail.body.to_s, 'Locale: en'
    assert_includes mail.body.to_s, 'http://dummy.example.com/livechat/'
  end

  test 'visitors with an email are notified of the first unread reply only' do
    Livechat.config.mailer_from = 'chat@example.com'

    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    conversation = Livechat::Conversation.last
    conversation.update!(visitor_email: 'guest@example.com')

    assert_enqueued_emails 1 do
      Livechat::Notifications.agent_message(
        conversation.post_agent_message!(body: 'hi!', agent_id: 1, agent_label: 'Ada')
      )
      Livechat::Notifications.agent_message(
        conversation.post_agent_message!(body: 'still there?', agent_id: 1, agent_label: 'Ada')
      )
    end

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal ['guest@example.com'], mail.to
    assert_includes mail.body.to_s, '2 unread replies'
    assert_includes mail.body.to_s, 'hi!'
    assert_includes mail.body.to_s, 'still there?'
  end
end
