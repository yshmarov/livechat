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

  test 'a message with a file needs no body, but a bare message still does' do
    png = fixture_file_upload('pixel.png', 'image/png')
    with_file = @conversation.messages.new(author_type: 'visitor')
    with_file.files.attach(png)
    assert_predicate with_file, :valid?

    assert_not @conversation.messages.new(author_type: 'visitor').valid?
  end

  test 'preview names the attachment when a message is files-only' do
    png = fixture_file_upload('pixel.png', 'image/png')
    message = @conversation.messages.new(author_type: 'visitor')
    message.files.attach(png)
    message.save!

    assert_equal '📎 pixel.png', message.preview
  end

  test 'attachments_json and the widget/inbox JSON expose gated urls' do
    png = fixture_file_upload('pixel.png', 'image/png')
    message = @conversation.post_visitor_message!('look', files: [png])

    attachment = message.attachments_json.first
    assert_equal 'pixel.png', attachment[:name]
    assert attachment[:image]
    assert_match %r{\A/livechat/attachments/\d+\z}, attachment[:url]
    assert_equal attachment[:url], message.as_widget_json[:attachments].first[:url]
    assert_equal attachment[:url], message.as_inbox_json[:attachments].first[:url]
  end

  test 'attachments_json flags audio separately from images' do
    audio = fixture_file_upload('notes.txt', 'audio/webm')
    message = @conversation.post_visitor_message!('voice', files: [audio])

    attachment = message.attachments_json.first
    assert_not attachment[:image]
    assert attachment[:audio]
  end

  test 'a message carrying no files exposes an empty attachments array' do
    message = @conversation.post_visitor_message!('plain text')
    assert_equal [], message.as_widget_json[:attachments]
  end
end
