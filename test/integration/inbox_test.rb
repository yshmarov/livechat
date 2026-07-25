# frozen_string_literal: true

require 'test_helper'

class InboxTest < ActionDispatch::IntegrationTest
  test 'the inbox is forbidden until authorize_agent says otherwise' do
    get '/livechat'
    assert_response :forbidden
    assert_includes response.body, 'authorize_agent'
  end

  test 'lists conversations with unread badges and tab counts' do
    conversation = start_conversation(visitor_label: 'Grace')
    conversation.post_visitor_message!('anyone there?')
    start_conversation(token: 'other').resolve_by!('Ada')

    as_agent!
    get '/livechat'
    assert_response :ok
    assert_includes response.body, 'Grace'
    assert_includes response.body, 'anyone there?'
    assert_includes response.body, 'badge unread-count'
    assert_includes response.body, ">##{conversation.id}</a>"

    get '/livechat?status=resolved'
    assert_includes response.body, 'Visitor #'
  end

  test 'index and thread expose email and case id for referencing' do
    conversation = start_conversation(visitor_label: 'Grace', visitor_email: 'grace@example.com')
    conversation.post_visitor_message!('hello')

    as_agent!
    get '/livechat'
    assert_includes response.body, 'grace@example.com'

    get "/livechat/#{conversation.id}"
    assert_includes response.body, "#{conversation.display_name} <span class=\"case-id\">##{conversation.id}</span>"
    assert_includes response.body, 'grace@example.com'
    refute_includes response.body, 'Started'
  end

  test 'opening a thread marks visitor messages as read' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    get "/livechat/#{conversation.id}"
    assert_response :ok
    assert_equal 0, conversation.reload.unread_from_visitor_count
  end

  test 'replies are signed with the agent label' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    post "/livechat/#{conversation.id}/messages", params: { body: 'On it!' }
    assert_redirected_to %r{/livechat/#{conversation.id}}

    message = conversation.messages.chronological.last
    assert_equal 'agent', message.author_type
    assert_equal '42', message.agent_id
    assert_equal 'Ada Lovelace', message.agent_label
  end

  test 'two agents in one thread are distinct' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!(user: fake_user(id: 1, name: 'Ada', email: 'ada@example.com'))
    post "/livechat/#{conversation.id}/messages", params: { body: 'Looking into it' }

    as_agent!(user: fake_user(id: 2, name: 'Grace', email: 'grace@example.com'))
    post "/livechat/#{conversation.id}/messages", params: { body: 'Fixed!' }

    get "/livechat/#{conversation.id}"
    assert_includes response.body, 'Ada'
    assert_includes response.body, 'Grace'
    assert_equal %w[Ada Grace], conversation.messages.from_agent.chronological.map(&:agent_label)
  end

  test 'a user-less agent still gets an attribution' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    Livechat.config.authorize_agent = ->(_request) { true } # but no current_user
    post "/livechat/#{conversation.id}/messages", params: { body: 'hi' }

    message = conversation.messages.chronological.last
    assert_equal '0', message.agent_id
    assert_equal 'Support', message.agent_label
  end

  test 'resolve and reopen from the inbox leave system messages' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    post "/livechat/#{conversation.id}/resolve"
    assert conversation.reload.resolved?
    assert_equal 'Ada Lovelace', conversation.messages.where(event: 'resolved').last.agent_label

    post "/livechat/#{conversation.id}/reopen"
    assert conversation.reload.open?
  end

  test 'empty replies bounce back with an alert' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    post "/livechat/#{conversation.id}/messages", params: { body: '  ' }
    assert_redirected_to %r{/livechat/#{conversation.id}}
    follow_redirect!
    assert_includes response.body, 'flash alert'
  end

  test 'poll reports the latest message id' do
    conversation = start_conversation
    message = conversation.post_visitor_message!('hello')

    as_agent!
    get "/livechat/#{conversation.id}/poll"
    assert_equal message.id, response.parsed_body['latest']
  end

  test 'agent replies notify the visitor by email' do
    conversation = start_conversation(visitor_email: 'guest@example.com')
    conversation.post_visitor_message!('hello')
    Livechat.config.mailer_from = 'chat@example.com'

    as_agent!
    assert_difference -> { ActiveJob::Base.queue_adapter.enqueued_jobs.size }, 1 do
      post "/livechat/#{conversation.id}/messages", params: { body: 'We are on it' }
    end
  end

  test 'dashboard script is served same-origin' do
    get '/livechat/dashboard.js'
    assert_response :ok
    assert_includes response.body, 'livechat dashboard'
  end
end
