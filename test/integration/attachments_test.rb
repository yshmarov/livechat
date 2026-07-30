# frozen_string_literal: true

require 'test_helper'

class AttachmentsTest < ActionDispatch::IntegrationTest
  def png = fixture_file_upload('pixel.png', 'image/png')
  def txt = fixture_file_upload('notes.txt', 'text/plain')
  def audio = fixture_file_upload('notes.txt', 'audio/webm')

  test 'a visitor message can carry files, and the JSON describes them' do
    post '/livechat/widget/messages', params: { body: 'see attached', files: [png, txt] }
    assert_response :created

    attachments = response.parsed_body['message']['attachments']
    assert_equal 2, attachments.size
    image = attachments.find { |a| a['image'] }
    assert_equal 'pixel.png', image['name']
    assert_match %r{\A/livechat/attachments/\d+\z}, image['url']
    assert(attachments.any? { |a| a['name'] == 'notes.txt' && a['image'] == false })
  end

  test 'audio attachments are described for native playback' do
    post '/livechat/widget/messages', params: { body: 'voice note', files: [audio] }
    assert_response :created

    attachment = response.parsed_body['message']['attachments'].first
    assert_equal 'notes.txt', attachment['name']
    assert_equal false, attachment['image']
    assert_equal true, attachment['audio']
    assert_match %r{\A/livechat/attachments/\d+\z}, attachment['url']
  end

  test 'a file-only message with no body is allowed' do
    post '/livechat/widget/messages', params: { body: '', files: [png] }
    assert_response :created
    assert_equal 1, Livechat::Message.last.files.count
  end

  test 'a files-only message previews as a paperclip line in the inbox list' do
    post '/livechat/widget/messages', params: { body: '', files: [png] }
    assert_equal '📎 pixel.png', Livechat::Conversation.last.last_message_preview
  end

  test 'oversized files are rejected as a validation error' do
    Livechat.config.max_attachment_size = 10 # bytes

    post '/livechat/widget/messages', params: { body: 'big', files: [png] }
    assert_response :unprocessable_entity
    assert_match(/too large/i, response.parsed_body['errors'].first)
    assert_equal 0, Livechat::Message.count
  end

  test 'too many files are rejected' do
    Livechat.config.max_attachments = 1

    post '/livechat/widget/messages', params: { body: 'lots', files: [png, txt] }
    assert_response :unprocessable_entity
    assert_match(/too many/i, response.parsed_body['errors'].first)
  end

  test 'a content-type outside the allowlist is rejected' do
    Livechat.config.allowed_attachment_types = ['image/png']

    post '/livechat/widget/messages', params: { body: 'nope', files: [txt] }
    assert_response :unprocessable_entity
    assert_match(/isn't allowed|not allowed/i, response.parsed_body['errors'].first)
  end

  test 'with attachments switched off the files are dropped, not stored' do
    Livechat.config.attach_files = false

    post '/livechat/widget/messages', params: { body: 'text wins', files: [png] }
    assert_response :created
    assert_equal 0, Livechat::Message.last.files.count
  end

  test 'attachments can use a configured Active Storage service' do
    Livechat.config.storage_service = :livechat_test

    post '/livechat/widget/messages', params: { body: 'stored separately', files: [png] }
    assert_response :created

    assert_equal 'livechat_test', Livechat::Message.last.files.first.blob.service_name
  end

  test 'the owning guest can download their attachment, streamed inline for images' do
    post '/livechat/widget/messages', params: { body: 'mine', files: [png] }
    url = response.parsed_body['message']['attachments'].first['url']

    get url
    assert_response :ok
    assert_equal 'image/png', response.media_type
    assert_includes response.headers['Content-Disposition'], 'inline'
    assert_equal 'nosniff', response.headers['X-Content-Type-Options']
  end

  test 'non-image attachments download rather than render inline' do
    post '/livechat/widget/messages', params: { body: 'doc', files: [txt] }
    url = response.parsed_body['message']['attachments'].first['url']

    get url
    assert_response :ok
    assert_includes response.headers['Content-Disposition'], 'attachment'
  end

  test 'audio attachments stream inline for browser playback' do
    post '/livechat/widget/messages', params: { body: 'listen', files: [audio] }
    url = response.parsed_body['message']['attachments'].first['url']

    get url
    assert_response :ok
    assert_equal 'audio/webm', response.media_type
    assert_includes response.headers['Content-Disposition'], 'inline'
  end

  test 'another visitor cannot download an attachment that is not theirs' do
    post '/livechat/widget/messages', params: { body: 'private', files: [png] }
    url = response.parsed_body['message']['attachments'].first['url']

    other = open_session
    other.get url
    assert_equal 403, other.response.status
  end

  test 'an authorized agent can download any attachment' do
    post '/livechat/widget/messages', params: { body: 'for support', files: [png] }
    url = response.parsed_body['message']['attachments'].first['url']

    agent = open_session
    Livechat.config.authorize_agent = ->(_request) { true }
    agent.get url
    assert_equal 200, agent.response.status
  end

  test 'a missing attachment id is a 404' do
    post '/livechat/widget/messages', params: { body: 'hi', files: [png] }
    get '/livechat/attachments/999999'
    assert_response :not_found
  end

  test 'agents can attach files to their replies' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    post "/livechat/#{conversation.id}/messages", params: { body: 'here you go', files: [png] }
    assert_redirected_to %r{/livechat/#{conversation.id}}

    message = conversation.messages.from_agent.last
    assert_equal 1, message.files.count

    get "/livechat/#{conversation.id}"
    assert_includes response.body, 'att-img'
  end

  test 'agents can record-style audio replies and the inbox renders a player' do
    conversation = start_conversation
    conversation.post_visitor_message!('hello')

    as_agent!
    post "/livechat/#{conversation.id}/messages", params: { body: '', files: [audio] }
    assert_redirected_to %r{/livechat/#{conversation.id}}

    message = conversation.messages.from_agent.last
    assert_equal 1, message.files.count
    assert_equal true, message.attachments_json.first[:audio]

    get "/livechat/#{conversation.id}"
    assert_includes response.body, 'att-audio'
  end

  test 'the widget config advertises whether attachments are on' do
    get '/sample'
    assert_includes response.body, '"attachments":true'

    Livechat.config.attach_files = false
    get '/sample'
    assert_includes response.body, '"attachments":false'
  end
end
