# frozen_string_literal: true

require 'test_helper'

class VisitorApiTest < ActionDispatch::IntegrationTest
  test 'empty state for a visitor without a thread' do
    get '/livechat/widget/conversation'
    assert_response :ok
    assert_equal({ 'status' => nil, 'unread' => 0, 'email' => false, 'cable' => nil,
                   'typing' => false, 'messages' => [] },
                 response.parsed_body)
  end

  test 'first guest message starts a thread and sets the cookie' do
    post '/livechat/widget/messages',
         params: { body: 'hello', page_url: 'http://example.com/pricing', locale: 'en' },
         as: :json

    assert_response :created
    assert cookies['livechat_vid'].present?

    conversation = Livechat::Conversation.last
    assert_equal 'hello', conversation.last_message_preview
    assert_equal 'http://example.com/pricing', conversation.page_url
    assert_nil conversation.visitor_id

    # The follow-up lands in the same thread — and refreshes the context to
    # the visitor's latest page, not the one they started on.
    post '/livechat/widget/messages',
         params: { body: 'again', page_url: 'http://example.com/billing' }, as: :json
    assert_equal 1, Livechat::Conversation.count
    assert_equal 2, conversation.messages.count
    assert_equal 'http://example.com/billing', conversation.reload.page_url
  end

  test 'signed-in visitors are attributed and get no cookie' do
    sign_in!
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    assert_response :created

    conversation = Livechat::Conversation.last
    assert_equal '42', conversation.visitor_id
    assert_equal 'Ada Lovelace', conversation.visitor_label
    assert_equal 'ada@example.com', conversation.visitor_email
    assert_nil cookies['livechat_vid']
  end

  test 'blank messages are rejected' do
    post '/livechat/widget/messages', params: { body: '   ' }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, Livechat::Conversation.count
  end

  test 'guests are isolated from each other' do
    post '/livechat/widget/messages', params: { body: 'visitor one' }, as: :json

    other = open_session
    other.get '/livechat/widget/conversation'
    assert_equal [], other.response.parsed_body['messages']
  end

  test 'polling with after returns only newer messages and the unread count' do
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    first_id = response.parsed_body['message']['id']

    conversation = Livechat::Conversation.last
    conversation.post_agent_message!(body: 'hi there', agent_id: 1, agent_label: 'Ada')

    get "/livechat/widget/conversation?after=#{first_id}"
    body = response.parsed_body
    assert_equal 1, body['messages'].size
    assert_equal 'hi there', body['messages'].first['body']
    assert_equal 'Ada', body['messages'].first['label']
    assert_equal 1, body['unread']
  end

  test 'read marks agent replies as seen' do
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    conversation = Livechat::Conversation.last
    conversation.post_agent_message!(body: 'hi', agent_id: 1, agent_label: 'Ada')

    post '/livechat/widget/read'
    assert_response :no_content

    get '/livechat/widget/conversation'
    assert_equal 0, response.parsed_body['unread']
  end

  test 'typing hints are visible to the other side while fresh' do
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    conversation = Livechat::Conversation.last

    post '/livechat/widget/typing'
    assert_response :no_content

    as_agent!
    get "/livechat/#{conversation.id}/poll"
    assert_equal true, response.parsed_body['typing']

    post "/livechat/#{conversation.id}/typing"
    assert_response :no_content

    get '/livechat/widget/conversation'
    assert_equal true, response.parsed_body['typing']
  end

  test 'writing into a resolved thread reopens it' do
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    conversation = Livechat::Conversation.last
    conversation.resolve_by!('Ada')

    post '/livechat/widget/messages', params: { body: 'me again' }, as: :json
    assert conversation.reload.open?
  end

  test 'guests can leave an email; junk is rejected' do
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json

    post '/livechat/widget/email', params: { email: 'guest@example.com' }, as: :json
    assert_response :no_content
    assert_equal 'guest@example.com', Livechat::Conversation.last.visitor_email

    post '/livechat/widget/email', params: { email: 'nope' }, as: :json
    assert_response :unprocessable_entity
  end

  test 'email without a thread is a 404' do
    post '/livechat/widget/email', params: { email: 'guest@example.com' }, as: :json
    assert_response :not_found
  end

  test 'a guest who signs in keeps their thread' do
    post '/livechat/widget/messages', params: { body: 'as guest' }, as: :json
    conversation = Livechat::Conversation.last

    sign_in!
    get '/livechat/widget/conversation'

    assert_equal '42', conversation.reload.visitor_id
    assert_equal 'Ada Lovelace', conversation.visitor_label
    assert_equal 'as guest', response.parsed_body['messages'].first['body']
  end

  test 'everything is off when disabled' do
    Livechat.config.enabled = ->(_request) { false }

    get '/livechat/widget/conversation'
    assert_response :forbidden
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    assert_response :forbidden
  end

  test 'agent display names are filtered before reaching the visitor' do
    Livechat.config.agent_display_name = ->(_label) { 'Support team' }
    post '/livechat/widget/messages', params: { body: 'hello' }, as: :json
    Livechat::Conversation.last.post_agent_message!(body: 'hi', agent_id: 1,
                                                    agent_label: 'ada@corp-internal.com')

    get '/livechat/widget/conversation'
    labels = response.parsed_body['messages'].map { |m| m['label'] }
    assert_includes labels, 'Support team'
    refute_includes response.body, 'corp-internal'
  end
end
