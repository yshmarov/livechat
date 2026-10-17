# frozen_string_literal: true

require 'test_helper'

class InboxSystemTest < ApplicationSystemTestCase
  setup do
    Livechat.config.authorize_agent = ->(_request) { true }
    Livechat.config.attach_files = false
    @forgery_protection = ActionController::Base.allow_forgery_protection
    @per_form_tokens = ActionController::Base.per_form_csrf_tokens
    @remote_forms = ActionView::Helpers::FormHelper.form_with_generates_remote_forms
    @embedded_tokens = ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms
    ActionController::Base.allow_forgery_protection = true
    ActionController::Base.per_form_csrf_tokens = true
    @conversation = start_conversation(visitor_label: 'Grace')
    @conversation.post_visitor_message!('Can you help with my account?')
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery_protection
    ActionController::Base.per_form_csrf_tokens = @per_form_tokens
    ActionView::Helpers::FormHelper.form_with_generates_remote_forms = @remote_forms
    ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms = @embedded_tokens
  end

  test 'resolve and reopen use valid per-form CSRF tokens on both inbox views' do
    ["/livechat/#{@conversation.id}", "/livechat?conversation_id=#{@conversation.id}"].each do |path|
      visit path
      within '.status-switch' do
        click_button 'Resolved'
      end
      assert_selector '.status-resolved.current'
      assert @conversation.reload.resolved?
      within '.status-switch' do
        click_button 'Open'
      end
      assert_selector '.status-open.current'
      assert @conversation.reload.open?
    end
  end

  test 'status changes and replies work with legacy remote form defaults without Rails UJS' do
    ActionView::Helpers::FormHelper.form_with_generates_remote_forms = true
    ActionView::Helpers::FormTagHelper.embed_authenticity_token_in_remote_forms = false
    visit "/livechat?conversation_id=#{@conversation.id}"
    within '.status-switch' do
      click_button 'Resolved'
    end
    assert_selector '.status-resolved.current'
    within '.status-switch' do
      click_button 'Open'
    end
    assert_selector '.status-open.current'
    fill_in 'Write your reply…', with: 'A reply from the legacy host'
    within 'form.reply' do
      click_button 'Send'
    end
    assert_selector '.msg.agent', text: 'A reply from the legacy host'
  end

  test 'keyboard replies return focus to the split-pane composer without focusing it on entry' do
    visit "/livechat?conversation_id=#{@conversation.id}"
    assert_no_selector '.reply textarea:focus'
    fill_in 'Write your reply…', with: 'First keyboard reply'
    find('.reply textarea').send_keys(%i[control enter])
    assert_selector '.msg.agent', text: 'First keyboard reply'
    assert_selector '.reply textarea:focus'
    assert_equal '', find('.reply textarea').value

    find('.reply textarea:focus').send_keys('Second keyboard reply', %i[meta enter])
    assert_selector '.msg.agent', text: 'Second keyboard reply'
    assert_selector '.reply textarea:focus'
    assert_equal 2, @conversation.messages.from_agent.count
  end

  test 'keyboard replies retain focus on the standalone thread' do
    visit "/livechat/#{@conversation.id}"
    fill_in 'Write your reply…', with: 'Standalone keyboard reply'
    find('.reply textarea').send_keys(%i[control enter])
    assert_selector '.msg.agent', text: 'Standalone keyboard reply'
    assert_selector '.reply textarea:focus'
  end
end
