# frozen_string_literal: true

require 'test_helper'

class ConversationTest < ActiveSupport::TestCase
  test 'requires some visitor identity' do
    conversation = Livechat::Conversation.new
    assert_not conversation.valid?

    assert Livechat::Conversation.new(visitor_token: 'abc').valid?
    assert Livechat::Conversation.new(visitor_id: '42').valid?
  end

  test 'validates visitor_email when present' do
    conversation = start_conversation
    conversation.visitor_email = 'not-an-email'
    assert_not conversation.valid?

    conversation.visitor_email = 'someone@example.com'
    assert conversation.valid?
  end

  test 'for_visitor prefers signed-in identity and ignores claimed guest threads' do
    guest = start_conversation(token: 'cookie-1')
    mine = Livechat::Conversation.create!(visitor_id: '42')

    assert_equal mine, Livechat::Conversation.for_visitor(visitor_id: '42', visitor_token: 'cookie-1')
    assert_equal guest, Livechat::Conversation.for_visitor(visitor_token: 'cookie-1')

    guest.update!(visitor_id: '7')
    assert_nil Livechat::Conversation.for_visitor(visitor_token: 'cookie-1')
  end

  test 'claim! adopts guest threads for the signed-in user' do
    guest = start_conversation(token: 'cookie-1')

    Livechat::Conversation.claim!(visitor_token: 'cookie-1', visitor_id: 42, visitor_label: 'Ada')

    assert_equal '42', guest.reload.visitor_id
    assert_equal 'Ada', guest.visitor_label
    assert_equal guest, Livechat::Conversation.for_visitor(visitor_id: '42')
  end

  test 'post_visitor_message! reopens a resolved conversation' do
    conversation = start_conversation
    conversation.resolve_by!('Ada')
    assert conversation.resolved?

    conversation.post_visitor_message!('hello again')

    assert conversation.reload.open?
    assert_equal 'hello again', conversation.messages.chronological.last.body
  end

  test 'resolve and reopen leave signed system messages, once' do
    conversation = start_conversation

    conversation.resolve_by!('Ada')
    conversation.resolve_by!('Ada') # no-op
    assert_equal 1, conversation.messages.where(event: 'resolved').count
    assert_equal 'Ada', conversation.messages.last.agent_label

    conversation.reopen_by!('Grace')
    assert conversation.open?
    assert_equal 1, conversation.messages.where(event: 'reopened').count
  end

  test 'messages refresh the cached inbox-list fields' do
    conversation = start_conversation
    conversation.post_visitor_message!('first message')

    assert_equal 'first message', conversation.reload.last_message_preview
    assert_not_nil conversation.last_activity_at

    # System messages bump activity but never become the preview.
    conversation.resolve_by!('Ada')
    assert_equal 'first message', conversation.reload.last_message_preview
  end

  test 'read tracking is per side' do
    conversation = start_conversation
    conversation.post_visitor_message!('from visitor')
    conversation.post_agent_message!(body: 'from agent', agent_id: 1, agent_label: 'Ada')

    assert_equal 1, conversation.unread_from_visitor_count

    conversation.mark_read_for_agent!
    assert_equal 0, conversation.unread_from_visitor_count
    assert conversation.messages.from_agent.unread.exists?

    conversation.mark_read_for_visitor!
    assert_not conversation.messages.from_agent.unread.exists?
  end

  test 'display_name falls back from label to email to id' do
    conversation = start_conversation
    assert_equal "Visitor ##{conversation.id}", conversation.display_name

    conversation.update!(visitor_email: 'g@example.com')
    assert_equal 'g@example.com', conversation.display_name

    conversation.update!(visitor_label: 'Grace')
    assert_equal 'Grace', conversation.display_name
  end
end
