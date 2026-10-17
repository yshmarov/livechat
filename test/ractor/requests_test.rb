# frozen_string_literal: true

# A separate process: ractorize! freezes Rails and cannot share a process with
# the ordinary suite, whose tests deliberately replace configuration per test.
require 'tmpdir'
require 'fileutils'
require 'json'
require 'rack/mock'

ENV['RAILS_ENV'] = 'ractor'
ractor_directory = Dir.mktmpdir('livechat-ractor-')
ENV['DATABASE_URL'] = "sqlite3:#{ractor_directory}/test.sqlite3"
at_exit { FileUtils.remove_entry(ractor_directory) }

require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'active_storage/engine' if ENV['RACTOR_MEDIA'] == '1'
require 'action_mailer/railtie'
require 'action_cable/engine' if ENV['RACTOR_CABLE'] == '1'
require 'livechat'
require 'minitest/autorun'
require 'active_support/ractors'

raise 'Use Rails edge and Ruby 4.0+ for test:ractor' unless Rails::Application.method_defined?(:ractorize!) &&
                                                            defined?(Ractor.shareable_lambda)

ActiveSupport::Ractors.unshareable_proc_action = :raise
FileUtils.mkdir_p("#{ractor_directory}/config/environments")
File.write("#{ractor_directory}/config/environments/ractor.rb", "# Dedicated Ractor host\n")

class RactorHost < Rails::Application
  config.load_defaults 7.1
  config.secret_key_base = 'ractor-test-secret-not-used-outside-tests'
  config.eager_load = true
  config.enable_reloading = false
  config.hosts = []
  config.logger = ActiveSupport::Ractors::Logger.new(ENV['RACTOR_DEBUG'] ? $stderr : nil)
  config.cache_store = :null_store
  config.active_job.queue_adapter = :inline
  config.public_file_server.enabled = false
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.active_record.maintain_test_schema = false
  config.i18n.available_locales = %i[en fr]
end
if defined?(ActiveStorage)
  RactorHost.config.active_storage.service = :ractor_test
  RactorHost.config.active_storage.service_configurations = {
    'ractor_test' => { 'service' => 'Disk', 'root' => "#{ractor_directory}/storage" }
  }
  RactorHost.config.active_job.queue_adapter = :inline
end
if defined?(ActionCable)
  RactorHost.config.action_cable.connection_class = Ractor.shareable_proc { ActionCable::Connection::Base }
  RactorHost.config.action_cable.cable = { 'adapter' => 'test' }
  RactorHost.config.action_cable.mount_path = nil
  Livechat.config.action_cable = true
end
RactorHost.config.root = ractor_directory
File.write("#{ractor_directory}/config/routes.rb", "Rails.application.routes.draw { mount_livechat at: '/livechat' }\n")
Livechat.config.enabled_environments = %w[ractor] if Livechat.config.respond_to?(:enabled_environments)
# A shareable test counter. Mutable storage lives on the main Ractor, so the
# test proves that successive worker Ractors share a rate-limit bucket.
class RactorCounter
  @counts = {}

  def self.increment(key, _amount = 1, **_options)
    if Ractor.main?
      @counts[key] = @counts.fetch(key, 0) + 1
    else
      shared_key = Ractor.make_shareable(key, copy: true)
      ActiveSupport::Ractors.on_main(self) { increment(shared_key) }
    end
  end
end

Livechat.config.rate_limit = Livechat.config.rate_limit.merge(store: RactorCounter, to: 2, by: -> { request.remote_ip })
RactorHost.initialize!
require_relative '../support/schema'

RactorUser = Data.define(:id, :email, :name)
Livechat.configure do |config|
  config.enabled = ->(request) { request.get_header('HTTP_X_DISABLED') != 'yes' }
  config.authorize_agent = ->(request) { request.get_header('HTTP_X_ADMIN') == 'yes' }
  config.current_user = lambda { |request|
    RactorUser.new(id: request.get_header('HTTP_X_USER'), email: 'ractor@example.com', name: 'Ractor visitor')
  }
  config.on_visitor_message = ->(message) { message.conversation.update_column(:visitor_label, 'notification ran') }
  config.greeting = ->(request) { "Hello #{request.get_header('HTTP_X_USER')}" }
end
Rails.application.ractorize!

class RactorRequestsTest < Minitest::Test
  def start_request(method, path, params: {}, headers: {})
    input = params.is_a?(String) ? params : Rack::Utils.build_nested_query(params)
    content_type = headers.fetch('CONTENT_TYPE', 'application/x-www-form-urlencoded')
    options = headers.merge(method: method, 'CONTENT_TYPE' => content_type,
                            'CONTENT_LENGTH' => input.bytesize.to_s)
    env = Rack::MockRequest.env_for(path, options)
    env.delete('rack.input')
    env.delete('rack.errors')
    Ractor.new(env, input) do |environment, data|
      environment['rack.input'] = StringIO.new(data)
      environment['rack.errors'] = StringIO.new
      status, response_headers, response_body = Rails.application.call(environment)
      body = +''
      response_body.each { |part| body << part }
      response_body.close if response_body.respond_to?(:close)
      [status, response_headers, body]
    end
  end

  def request(...) = start_request(...).value

  def test_rate_limit_counts_across_worker_ractors
    headers = { 'REMOTE_ADDR' => '198.51.100.42', 'HTTP_X_USER' => 'rate-user' }
    params = { body: 'rate test' }
    statuses = 3.times.map do
      request('POST', '/livechat/widget/messages', params: params, headers: headers).first
    end
    assert_equal [201, 201, 429], statuses
  end

  def upload(path, fields:, field:, filename:, bytes:, content_type:, headers: {})
    boundary = 'ractor-upload-boundary'
    input = fields.map do |key, value|
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
    end.join
    input << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{field}\"; filename=\"#{filename}\"\r\n"
    input << "Content-Type: #{content_type}\r\n\r\n#{bytes}\r\n--#{boundary}--\r\n"
    headers = headers.merge('CONTENT_TYPE' => "multipart/form-data; boundary=#{boundary}",
                            'REMOTE_ADDR' => '198.51.100.43', 'HTTP_X_USER' => 'upload')
    request('POST', path, params: input, headers: headers)
  end

  def test_upload_runs_in_a_worker_ractor
    skip 'Run with RACTOR_MEDIA=1 for Active Storage integration' unless defined?(ActiveStorage)

    bytes = File.binread(File.expand_path('../fixtures/files/pixel.png', __dir__))
    status, _, body = upload('/livechat/widget/messages', fields: { 'body' => 'upload' },
                                                          field: 'files[]', filename: 'pixel.png',
                                                          bytes: bytes, content_type: 'image/png')
    assert_equal 201, status, body
    message = Livechat::Message.find_by!(body: 'upload')
    assert_equal bytes, message.files.first.download
    assert_equal Digest::MD5.base64digest(bytes), message.files.first.blob.checksum
  end

  def test_media_streams_through_the_authorized_engine_route
    skip 'Run with RACTOR_MEDIA=1 for Active Storage integration' unless defined?(ActiveStorage)

    bytes = 'ractor-media-bytes'
    conversation = Livechat::Conversation.create!(visitor_id: 'media')
    record = conversation.messages.create!(author_type: 'visitor', body: 'media')
    record.files.attach(io: StringIO.new(bytes), filename: 'pixel.png', content_type: 'image/png',
                        metadata: { analyzed: true })
    path = "/livechat/attachments/#{record.files.first.id}"
    allowed = { 'HTTP_X_USER' => 'media' }
    status, _, body = request('GET', path)
    assert_equal 403, status, body
    status, headers, body = request('GET', path, headers: allowed)
    assert_equal 200, status, body
    assert_equal bytes, body
    assert_includes headers['cache-control'], 'private'
    assert_includes headers['cache-control'], 'no-store'
  end

  def test_simultaneous_worker_requests
    workers = 2.times.map { start_request('GET', '/livechat/widget.js') }
    workers.each do |worker|
      status, _, body = worker.value
      assert_equal 200, status, body
    end
  end

  def test_assets_and_dashboard_render_in_non_main_ractors
    2.times do
      %w[widget.js dashboard.css dashboard.js].reject(&:empty?).each do |asset|
        status, headers, body = request('GET', "/livechat/#{asset}")
        assert_equal 200, status, body
        refute_empty body
        assert_includes headers['content-type'], asset.end_with?('.css') ? 'css' : 'javascript'
      end
      status, _, body = request('GET', '/livechat')
      assert_equal 403, status, body
      status, _, body = request('GET', '/livechat', headers: { 'HTTP_X_ADMIN' => 'yes' })
      assert_equal 200, status, body
    end
  end

  def test_messages_resolve_identity_settings_and_notification_callbacks
    %w[alpha beta].each do |visitor|
      status, _, body = request('POST', '/livechat/widget/messages', params: { body: "Ractor #{visitor}" },
                                                                     headers: { 'HTTP_X_USER' => visitor })
      assert_equal 201, status, body
      record = Livechat::Conversation.find_by!(visitor_id: visitor)
      assert_equal 'notification ran', record.visitor_label
      assert_equal "Ractor #{visitor}", record.messages.last.body
    end
    status, _, body = request('GET', '/livechat/widget/conversation', headers: { 'HTTP_X_USER' => 'alpha' })
    assert_equal 200, status, body
    if defined?(ActionCable)
      payload = JSON.parse(body)
      assert_equal '/cable', payload.fetch('cable').fetch('url')
      token = payload.fetch('cable').fetch('stream')
      conversation = Livechat::Conversation.find_by!(visitor_id: 'alpha')
      assert_equal "livechat:conversation:#{conversation.id}", Livechat.verify_stream(token)
      broadcasts = ActionCable.server.pubsub.broadcasts("livechat:conversation:#{conversation.id}")
      refute_empty broadcasts
    end
    assert_includes body, 'Ractor alpha'
    refute_includes body, 'Ractor beta'
    status, _, body = request('POST', '/livechat/widget/messages', params: { body: 'blocked' },
                                                                   headers: { 'HTTP_X_DISABLED' => 'yes' })
    assert_equal 403, status, body
    refute Livechat::Message.exists?(body: 'blocked')
  end
end
