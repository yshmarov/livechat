# frozen_string_literal: true

require 'test_helper'

class WidgetTagTest < ActionDispatch::IntegrationTest
  test 'renders the config block and a nonced same-origin script' do
    get '/sample'
    assert_includes response.body, 'data-livechat-config'
    assert_includes response.body, '<script src="/livechat/widget.js?v='
    assert_includes response.body, 'nonce="testnonce"'
    assert_includes response.body, '"authenticated":false'
  end

  test 'marks signed-in visitors as authenticated' do
    sign_in!
    get '/sample'
    assert_includes response.body, '"authenticated":true'
  end

  test 'serves the widget code as same-origin JavaScript with an ETag' do
    get '/livechat/widget.js'
    assert_response :ok
    assert_equal 'text/javascript', response.media_type
    assert_includes response.body, 'livechat widget'
    assert response.headers['ETag'].present?
  end

  test 'fingerprinted URL gets immutable caching' do
    get "/livechat/widget.js?v=#{Livechat::Widget.fingerprint}"
    assert_includes response.headers['Cache-Control'], 'public'

    get '/livechat/widget.js?v=stale'
    assert_not_includes response.headers['Cache-Control'].to_s, 'max-age=31556952'
  end

  test 'renders nothing when disabled' do
    Livechat.config.enabled = ->(_request) { false }
    get '/sample'
    refute_includes response.body, 'data-livechat-config'
  end

  test 'is rtl for rtl locales' do
    get '/sample', params: {}, headers: {}
    assert_includes response.body, '"rtl":false'

    I18n.with_locale(:ar) do
      assert_includes Livechat::Widget.config_json(locale: :ar, authenticated: false), '"rtl":true'
    end
  end

  test 'escapes </script> inside config values' do
    Livechat.config.greeting = 'hi </script><script>alert(1)'
    get '/sample'
    # ActiveSupport's to_json escapes "<" as <, so a value can never
    # close the <script> block early.
    refute_includes response.body, 'hi </script>'
    assert_includes response.body, 'hi \u003c/script'
  end

  test 'livechat_button renders a plain opener' do
    get '/sample'
    assert_includes response.body, 'data-livechat-open'
    assert_includes response.body, '>Chat with us</button>'
  end
end
