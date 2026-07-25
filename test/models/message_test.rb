# frozen_string_literal: true

require 'test_helper'

class MessageTest < ActiveSupport::TestCase
  setup do
    @conversation = start_conversation
  end

  test 'visitor and agent messages need a body; system messages need an event' do
    assert_not @conversation.messages.new(author_type: 'visitor').valid?
    assert_not @conversation.messages.new(author_type: 'system').valid?
    assert_not @conversation.messages.new(author_type: 'system', event: 'nonsense').valid?
    assert_not @conversation.messages.new(author_type: 'visitor', body: 'hi', event: 'resolved').valid?

    assert @conversation.messages.new(author_type: 'visitor', body: 'hi').valid?
    assert @conversation.messages.new(author_type: 'system', event: 'resolved').valid?
  end

  test 'agent messages carry attribution' do
    assert_not @conversation.messages.new(author_type: 'agent', body: 'hi').valid?
    assert @conversation.messages.new(author_type: 'agent', body: 'hi', agent_id: '1').valid?
  end

  test 'body is length-capped' do
    message = @conversation.messages.new(author_type: 'visitor', body: 'x' * 5_001)
    assert_not message.valid?
  end

  test 'public_label runs agent names through agent_display_name' do
    message = @conversation.post_agent_message!(body: 'hi', agent_id: 1, agent_label: 'Ada Lovelace')
    assert_equal 'Ada Lovelace', message.public_label

    Livechat.config.agent_display_name = ->(label) { label.split.first }
    assert_equal 'Ada', message.public_label

    # Blank display names fall back to a constant, so visitors always see a sender.
    Livechat.config.agent_display_name = ->(_label) {}
    assert_equal 'Support', message.public_label
  end

  test 'as_widget_json exposes no body for system messages and no label for visitors' do
    visitor = @conversation.post_visitor_message!('hello')
    assert_equal 'visitor', visitor.as_widget_json[:author]
    assert_nil visitor.as_widget_json[:label]

    @conversation.resolve_by!('Ada')
    system = @conversation.messages.chronological.last
    assert_equal 'resolved', system.as_widget_json[:event]
    assert_nil system.as_widget_json[:body]
  end

  test 'after_id paginates polling' do
    first = @conversation.post_visitor_message!('one')
    second = @conversation.post_visitor_message!('two')

    assert_equal [second], @conversation.messages.after_id(first.id).to_a
  end
end
