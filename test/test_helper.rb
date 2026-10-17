# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative 'dummy/config/environment'
require 'rails/test_help'
require 'rack/test'

require_relative 'support/schema'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1200, 900]

  # Browser requests run through the app server on a separate connection, so
  # their writes cannot live inside the test process's wrapping transaction.
  self.use_transactional_tests = false

  setup { purge_livechat_data! }
  teardown { purge_livechat_data! }

  private

  def purge_livechat_data!
    ActiveStorage::Attachment.delete_all
    ActiveStorage::Blob.delete_all
    Livechat::Message.delete_all
    Livechat::Conversation.delete_all
  end
end

module ActiveSupport
  class TestCase
    include ActionDispatch::TestProcess::FixtureFile # fixture_file_upload in model tests

    self.use_transactional_tests = true
    self.file_fixture_path = File.expand_path('fixtures/files', __dir__)

    # Start every test from a fresh config, so a tweak in one test can never
    # leak into another. The rate limiter counts per IP in Rails.cache, so
    # clear that too.
    setup do
      Livechat.instance_variable_set(:@config, Livechat::Configuration.new)
      Rails.cache.clear
      ActionMailer::Base.deliveries.clear
    end

    teardown do
      Livechat.instance_variable_set(:@config, nil)
    end

    private

    # Most inbox tests need an agent; the default gate is development-only.
    def as_agent!(user: fake_user)
      Livechat.config.authorize_agent = ->(_request) { true }
      Livechat.config.current_user = ->(_request) { user }
    end

    def sign_in!(user: fake_user)
      Livechat.config.current_user = ->(_request) { user }
    end

    def fake_user(id: 42, name: 'Ada Lovelace', email: 'ada@example.com')
      Struct.new(:id, :name, :email).new(id, name, email)
    end

    def start_conversation(token: 'guest-token', **attrs)
      Livechat::Conversation.create!(visitor_token: token, **attrs)
    end
  end
end
