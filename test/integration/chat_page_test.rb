# frozen_string_literal: true

require 'test_helper'

class ChatPageTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test 'serves the chat page to any visitor, outside the inbox and its gate' do
    get '/livechat/chat'

    assert_response :ok
    assert_includes response.body, 'data-livechat-chat'
    assert_includes response.body, 'data-livechat-config'
    assert_includes response.body, '<script src="/livechat/widget.js?v='
    assert_includes response.body, '<meta name="robots" content="noindex">'
    assert_includes response.body, "<title>#{Livechat.app_name}</title>"
    refute_includes response.body, 'lvc-dashboard' # not the inbox layout
  end

  test 'carries the CSRF token the widget posts with' do
    protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get '/livechat/chat'
    assert_includes response.body, 'name="csrf-token"'
  ensure
    ActionController::Base.allow_forgery_protection = protection
  end

  test 'the inbox still answers below the mount path' do
    as_agent!
    conversation = start_conversation
    conversation.post_visitor_message!('Hello')

    get "/livechat/#{conversation.id}"
    assert_response :ok
    assert_includes response.body, 'Hello'
  end

  test 'is forbidden where the widget is disabled' do
    Livechat.config.enabled = ->(_request) { false }
    get '/livechat/chat'
    assert_response :forbidden
  end

  test 'is gone when chat_path is false' do
    Livechat.config.chat_path = false

    get '/livechat/chat'
    assert_response :not_found

    get '/sample'
    assert_includes response.body, '"chatUrl":null'
  end

  test 'redirects to a page of the host when chat_path names one' do
    Livechat.config.chat_path = '/support'
    get '/livechat/chat'
    assert_redirected_to '/support'

    Livechat.config.chat_path = 'https://help.example.com/chat'
    get '/livechat/chat'
    assert_redirected_to 'https://help.example.com/chat'
  end

  test 'the redirect to a host page keeps the language' do
    Livechat.config.chat_path = '/support'
    get '/livechat/chat', params: { locale: 'fr' }
    assert_redirected_to '/support?locale=fr'
  end

  test 'chat_path naming the engine page itself does not loop' do
    Livechat.config.chat_path = '/livechat/chat'
    get '/livechat/chat'
    assert_response :ok
  end

  test 'renders in the language the link asks for, and falls back on anything else' do
    get '/livechat/chat', params: { locale: 'fr' }
    assert_includes response.body, '<html lang="fr">'
    assert_includes response.body, '"locale":"fr"'

    get '/livechat/chat', params: { locale: 'de' } # a locale the app doesn't offer
    assert_includes response.body, '<html lang="en">'

    get '/livechat/chat', params: { locale: 'xx' }
    assert_includes response.body, '<html lang="en">'
  end

  test 'is right-to-left in rtl languages' do
    get '/livechat/chat', params: { locale: 'ar' }
    assert_includes response.body, '<html lang="ar" dir="rtl">'
  end

  test 'the widget config carries the chat page for the panel link' do
    get '/sample'
    assert_includes response.body, '"chatUrl":"/livechat/chat"'

    Livechat.config.chat_path = '/support'
    get '/sample'
    assert_includes response.body, '"chatUrl":"/support"'
  end

  test 'livechat_chat renders only the element the widget fills' do
    get '/support'
    assert_includes response.body, '<div data-livechat-chat="" id="host-chat" style="height: 500px"></div>'
    assert_equal 1, response.body.scan('data-livechat-config').size

    Livechat.config.enabled = ->(_request) { false }
    get '/support'
    refute_includes response.body, 'data-livechat-chat'
  end

  test 'Livechat.chat_path follows chat_path and mount_path' do
    assert_equal '/livechat/chat', Livechat.chat_path

    Livechat.config.mount_path = '/help/'
    assert_equal '/help/chat', Livechat.chat_path

    Livechat.config.chat_path = '/support'
    assert_equal '/support', Livechat.chat_path

    assert_equal '/support?locale=fr', Livechat.chat_path(locale: :fr)

    Livechat.config.chat_path = '/help?tab=chat'
    assert_equal '/help?tab=chat&locale=fr', Livechat.chat_path(locale: 'fr')

    Livechat.config.chat_path = false
    assert_nil Livechat.chat_path
    assert_nil Livechat.chat_path(locale: 'fr')
  end

  test 'the reply email links to the chat page on the origin the visitor wrote from' do
    mail = reply_mail(page_url: 'https://www.example.com/pricing', locale: 'de')
    assert_includes mail, 'https://www.example.com/livechat/chat?locale=de'
    refute_includes mail, 'https://www.example.com/pricing'
  end

  test 'a signed-in visitor keeps the link to their last page, which can sign them in' do
    mail = reply_mail(page_url: 'https://app.example.com/orders', locale: 'en', visitor_id: '42')
    assert_includes mail, 'https://app.example.com/orders'
    refute_includes mail, '/livechat/chat'

    mail = reply_mail(page_url: nil, locale: nil, visitor_id: '43')
    assert_includes mail, 'http://dummy.example.com/livechat/chat'

    Livechat.config.chat_path = '/support'
    mail = reply_mail(page_url: 'https://app.example.com/orders', locale: 'en', visitor_id: '44')
    assert_includes mail, 'http://dummy.example.com/support?locale=en'
  end

  test 'the reply email falls back to the mailer host without a page' do
    mail = reply_mail(page_url: nil, locale: nil)
    assert_includes mail, 'http://dummy.example.com/livechat/chat'
  end

  test 'a chat page of the host is linked on the app host, not the embedding site' do
    Livechat.config.chat_path = '/support'
    mail = reply_mail(page_url: 'https://www.example.com/pricing', locale: 'en')
    assert_includes mail, 'http://dummy.example.com/support?locale=en'
  end

  test 'without a chat page the reply email links the last page, as before' do
    Livechat.config.chat_path = false
    mail = reply_mail(page_url: 'https://www.example.com/pricing', locale: 'en')
    assert_includes mail, 'https://www.example.com/pricing'
    refute_includes mail, '/livechat/chat'
  end

  private

  def reply_mail(page_url:, locale:, visitor_id: nil)
    Livechat.config.mailer_from = 'chat@example.com'
    conversation = start_conversation(token: "token-#{visitor_id}", visitor_email: 'guest@example.com',
                                      page_url:, locale:, visitor_id:)
    message = conversation.post_agent_message!(body: 'Answered!', agent_id: '1', agent_label: 'Ada')
    Livechat::Mailer.new_agent_reply(message).body.to_s
  end
end
