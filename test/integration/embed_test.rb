# frozen_string_literal: true

require 'test_helper'

# The widget on a page this app does not render: a static site proxying the
# mount path through to Rails, where there is no layout helper to call and no
# Rails session to mint a CSRF token from.
class EmbedTest < ActionDispatch::IntegrationTest
  EMBED_ORIGIN = 'https://marketing.example.com'

  test 'embed.js carries the config and loads the fingerprinted widget' do
    get '/livechat/embed.js'

    assert_response :ok
    assert_equal 'text/javascript', response.media_type
    assert_includes response.body, 'data-livechat-config'
    assert_includes response.body, "/livechat/widget.js?v=#{Livechat::Widget.fingerprint}"
    assert_includes response.body, '"endpoint":"/livechat/widget"'
  end

  test 'embed.js is never cached, so per-visitor config cannot go stale' do
    get '/livechat/embed.js'

    assert_equal 'no-store', response.headers['Cache-Control']
  end

  test 'embed.js follows the locale the embedding page asks for' do
    get '/livechat/embed.js', params: { locale: 'fr' }
    assert_includes response.body, '"locale":"fr"'

    # An unknown locale falls back rather than raising at a visitor.
    get '/livechat/embed.js', params: { locale: 'klingon' }
    assert_includes response.body, '"locale":"en"'
  end

  test 'embed.js is empty when the widget is disabled for the request' do
    Livechat.config.enabled = ->(_request) { false }

    get '/livechat/embed.js'

    assert_response :ok
    assert_equal '', response.body.strip
  end

  test 'per-request settings let one app greet each surface differently' do
    Livechat.config.greeting = lambda do |request|
      request.origin == EMBED_ORIGIN ? 'Sales, not support' : 'How can we help?'
    end
    Livechat.config.show_launcher = ->(request) { request.origin == EMBED_ORIGIN }

    get '/livechat/embed.js', headers: { 'HTTP_ORIGIN' => EMBED_ORIGIN }
    assert_includes response.body, 'Sales, not support'
    assert_includes response.body, '"launcher":true'

    get '/livechat/embed.js'
    assert_includes response.body, 'How can we help?'
    assert_includes response.body, '"launcher":false'
  end

  test 'an allowlisted origin may write without a CSRF token' do
    with_forgery_protection do
      post '/livechat/widget/messages',
           params: { body: 'hello from the marketing site' }.to_json,
           headers: json_headers(origin: EMBED_ORIGIN)
    end

    assert_response :created
    assert_equal 'hello from the marketing site', Livechat::Conversation.last.last_message_preview
  end

  test 'an origin that is not allowlisted still needs a token' do
    with_forgery_protection do
      post '/livechat/widget/messages',
           params: { body: 'hello' }.to_json,
           headers: json_headers(origin: 'https://attacker.example.com')
    end

    assert_response 422
    assert_equal 0, Livechat::Conversation.count
  end

  # The exemption rests on a header only a browser can set. A client that sends
  # no Origin at all must not inherit it.
  test 'a request without an origin never counts as embedded' do
    with_forgery_protection do
      post '/livechat/widget/messages',
           params: { body: 'hello' }.to_json,
           headers: json_headers(origin: nil)
    end

    assert_response 422
    assert_equal 0, Livechat::Conversation.count
  end

  test 'the inbox is never exempted, whatever the origin claims' do
    as_agent!
    conversation = start_conversation

    with_forgery_protection do
      post "/livechat/#{conversation.id}/resolve", headers: { 'HTTP_ORIGIN' => EMBED_ORIGIN }
    end

    assert_response 422
    assert_equal 'open', conversation.reload.status
  end

  test 'a trailing slash on a configured origin still matches' do
    Livechat.config.allowed_embed_origins = ["#{EMBED_ORIGIN}/"]

    assert Livechat.embedded?(request_from(EMBED_ORIGIN))
  end

  test 'the public paths are the ones that need no session' do
    assert_equal ['/livechat/widget.js', '/livechat/embed.js', '/livechat/widget/', '/livechat/attachments/'],
                 Livechat.public_paths

    Livechat.config.mount_path = '/support/'
    assert_includes Livechat.public_paths, '/support/embed.js'
  end

  private

  def json_headers(origin:)
    headers = { 'CONTENT_TYPE' => 'application/json' }
    headers['HTTP_ORIGIN'] = origin if origin
    headers
  end

  def request_from(origin)
    ActionDispatch::Request.new(Rack::MockRequest.env_for('/', 'HTTP_ORIGIN' => origin))
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  setup do
    Livechat.config.allowed_embed_origins = [EMBED_ORIGIN]
  end
end
