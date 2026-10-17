# frozen_string_literal: true

require 'test_helper'

class InboxCsrfTest < ActionDispatch::IntegrationTest
  setup do
    as_agent!
    @forgery_protection = ActionController::Base.allow_forgery_protection
    @per_form_tokens = ActionController::Base.per_form_csrf_tokens
    ActionController::Base.allow_forgery_protection = true
    ActionController::Base.per_form_csrf_tokens = true
    @conversation = start_conversation
    @conversation.post_visitor_message!('A protected thread')
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery_protection
    ActionController::Base.per_form_csrf_tokens = @per_form_tokens
  end

  test 'status and reply endpoints still reject missing CSRF tokens' do
    post "/livechat/#{@conversation.id}/resolve"
    assert_response :unprocessable_entity
    assert @conversation.reload.open?

    assert_no_difference -> { @conversation.messages.count } do
      post "/livechat/#{@conversation.id}/messages", params: { body: 'An unverified reply' }
      assert_response :unprocessable_entity
    end
  end

  test 'a resolve token cannot authorize a reopen request' do
    get "/livechat/#{@conversation.id}"
    token = css_select('form.status-switch input[name=authenticity_token]').first['value']
    post "/livechat/#{@conversation.id}/resolve", params: { authenticity_token: token }
    assert_response :redirect
    assert @conversation.reload.resolved?

    post "/livechat/#{@conversation.id}/reopen", params: { authenticity_token: token }
    assert_response :unprocessable_entity
    assert @conversation.reload.resolved?
  end
end
