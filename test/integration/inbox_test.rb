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
    assert_includes response.body, "conversation_id=#{conversation.id}"

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

  test 'search matches visitor identity and message bodies, scoped to the tab' do
    billing = start_conversation(token: 'a', visitor_label: 'Grace')
    billing.post_visitor_message!('my INVOICE looks wrong')
    other = start_conversation(token: 'b', visitor_email: 'invoice-team@example.com')
    other.post_visitor_message!('hello')
    resolved = start_conversation(token: 'c')
    resolved.post_visitor_message!('invoice question')
    resolved.resolve_by!('Ada')

    as_agent!
    get '/livechat?q=invoice'
    assert_includes response.body, 'my INVOICE looks wrong' # body match
    assert_includes response.body, 'invoice-team@example.com' # email match
    refute_includes response.body, "conversation_id=#{resolved.id}" # resolved tab only

    get '/livechat?q=invoice&status=resolved'
    assert_includes response.body, "conversation_id=#{resolved.id}"

    get '/livechat?q=nothing-matches-this'
    refute_includes response.body, "conversation_id=#{billing.id}"
  end

  test 'index can render a selected conversation beside the list' do
    conversation = start_conversation(visitor_label: 'Grace', visitor_email: 'grace@example.com')
    message = conversation.post_visitor_message!('hello from the selected thread')

    as_agent!
    get "/livechat?conversation_id=#{conversation.id}"
    assert_response :ok
    assert_includes response.body, 'inbox-shell has-selected'
    assert_includes response.body, 'hello from the selected thread'
    assert_includes response.body, "message-#{message.id}"
    assert_includes response.body, 'Write your reply'
    assert_includes response.body, 'status-toggle is-open'
    assert message.reload.read?
  end

  test 'index lists the agents who worked each thread' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')
    conversation.post_agent_message!(body: 'hi', agent_id: 1, agent_label: 'Ada')
    conversation.post_agent_message!(body: 'me too', agent_id: 2, agent_label: 'Grace')
    conversation.post_agent_message!(body: 'again', agent_id: 1, agent_label: 'Ada')

    as_agent!
    get '/livechat'
    assert_includes response.body, '<span class="avatar color-'
    assert_includes response.body, 'title="Ada"'
    assert_includes response.body, 'title="Grace"'
    # Deduplicated: Ada wrote twice, appears once.
    assert_equal 1, response.body.scan('title="Ada"').size
  end

  test 'index poll token moves when anything changes' do
    as_agent!
    get '/livechat/poll'
    before = response.parsed_body['token']

    start_conversation.post_visitor_message!('new!')
    get '/livechat/poll'
    assert_not_equal before, response.parsed_body['token']
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

  test 'poll returns new messages after an id for live append, and marks them read' do
    conversation = start_conversation
    first = conversation.post_visitor_message!('hello')

    as_agent!
    conversation.post_agent_message!(body: 'hi there', agent_id: 1, agent_label: 'Ada')
    visitor_reply = conversation.post_visitor_message!('one more thing')

    get "/livechat/#{conversation.id}/poll?after=#{first.id}"
    body = response.parsed_body
    assert_equal(%w[agent visitor], body['messages'].map { |m| m['author'] })
    assert_equal 'hi there', body['messages'].first['body']
    assert_equal 'Ada', body['messages'].first['name']
    assert_equal 'one more thing', body['messages'].last['body']

    # The agent is viewing the thread, so the visitor's message is now read.
    assert visitor_reply.reload.read?
  end

  test 'poll renders system events as ready localized lines' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')
    conversation.resolve_by!('Ada')

    as_agent!
    get "/livechat/#{conversation.id}/poll?after=0"
    system = response.parsed_body['messages'].find { |m| m['author'] == 'system' }
    assert_match(/Ada resolved/, system['text'])
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
