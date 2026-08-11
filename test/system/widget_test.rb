# frozen_string_literal: true

require 'test_helper'

class WidgetSystemTest < ApplicationSystemTestCase
  test 'carries a visitor message through the inbox and returns the agent reply' do
    Livechat.config.authorize_agent = ->(_request) { true }
    Livechat.config.attach_files = false

    visit '/sample'
    find('#lvc-launcher').click

    within '#lvc-panel' do
      fill_in 'Write a message…', with: 'I need help with my account.'
      click_button 'Send'
      assert_selector '.lvc-msg.lvc-visitor', text: 'I need help with my account.'
    end

    conversation = Livechat::Conversation.last
    assert_equal 'I need help with my account.', conversation.messages.last.body

    visit "/livechat?conversation_id=#{conversation.id}"
    within '.detail-panel' do
      assert_text 'I need help with my account.'
      fill_in 'Write your reply…', with: 'We found it and fixed the account.'
      click_button 'Send'
      assert_text 'We found it and fixed the account.'
    end

    assert_equal 'agent', conversation.messages.reload.last.author_type

    visit '/sample'
    assert_selector '#lvc-panel', visible: true
    within '#lvc-panel' do
      assert_selector '.lvc-msg.lvc-agent', text: 'We found it and fixed the account.'
    end
  end
end
