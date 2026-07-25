# frozen_string_literal: true

require 'test_helper'

class ActionCablePushTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  test 'nothing is broadcast while push is off (the default)' do
    conversation = start_conversation

    assert_no_broadcasts('livechat:inbox') do
      conversation.post_visitor_message!('hello')
    end
  end

  test 'a new message nudges its conversation stream and the inbox stream' do
    Livechat.config.action_cable = true
    conversation = start_conversation

    assert_broadcasts("livechat:conversation:#{conversation.id}", 1) do
      assert_broadcasts('livechat:inbox', 1) do
        conversation.post_visitor_message!('hello')
      end
    end
  end

  test 'agent replies nudge the same streams' do
    Livechat.config.action_cable = true
    conversation = start_conversation

    assert_broadcasts('livechat:inbox', 1) do
      conversation.post_agent_message!(body: 'hi', agent_id: 1, agent_label: 'Ada')
    end
  end

  test 'the poll response carries a signed cable stream when push is on' do
    Livechat.config.action_cable = true
    post '/livechat/widget/messages', params: { body: 'hi' }, as: :json

    get '/livechat/widget/conversation'
    cable = response.parsed_body['cable']
    assert_equal '/cable', cable['url']
    assert Livechat.verify_stream(cable['stream']).start_with?('livechat:conversation:')
  end

  test 'the poll response has no cable block when push is off' do
    post '/livechat/widget/messages', params: { body: 'hi' }, as: :json

    get '/livechat/widget/conversation'
    assert_nil response.parsed_body['cable']
  end

  test 'the inbox list and thread carry a signed cable stream when push is on' do
    Livechat.config.action_cable = true
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    get '/livechat'
    assert_includes response.body, 'data-cable-url="/cable"'
    assert_includes response.body, 'data-cable-stream='

    get "/livechat/#{conversation.id}"
    assert_includes response.body, 'data-cable-stream='
  end

  test 'the inbox has no cable attributes when push is off' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    get "/livechat/#{conversation.id}"
    assert_not_includes response.body, 'data-cable-stream'
  end
end
