# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative 'dummy/config/environment'
require 'rails/test_help'

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :livechat_conversations, force: true do |t|
    t.string :visitor_token
    t.string :visitor_id
    t.string :visitor_label
    t.string :visitor_email
    t.string :status, null: false, default: 'open'
    t.string :last_message_preview
    t.datetime :last_activity_at
    t.string :page_url
    t.string :locale
    t.timestamps
  end
  add_index :livechat_conversations, :visitor_token
  add_index :livechat_conversations, :visitor_id
  add_index :livechat_conversations, :status
  add_index :livechat_conversations, :last_activity_at

  create_table :livechat_messages, force: true do |t|
    t.references :conversation, null: false, index: false
    t.string :author_type, null: false
    t.string :agent_id
    t.string :agent_label
    t.text :body
    t.string :event
    t.datetime :read_at
    t.timestamps
  end
  add_index :livechat_messages, %i[conversation_id id]

  # Active Storage — the host provides these in a real app (rails
  # active_storage:install); defined here so attachment tests have somewhere
  # to write.
  create_table :active_storage_blobs, force: true do |t|
    t.string   :key,          null: false
    t.string   :filename,     null: false
    t.string   :content_type
    t.text     :metadata
    t.string   :service_name, null: false
    t.bigint   :byte_size,    null: false
    t.string   :checksum
    t.datetime :created_at, null: false
  end
  add_index :active_storage_blobs, :key, unique: true

  create_table :active_storage_attachments, force: true do |t|
    t.string     :name,        null: false
    t.references :record,      null: false, polymorphic: true, index: false
    t.references :blob,        null: false
    t.datetime   :created_at,  null: false
  end
  add_index :active_storage_attachments,
            %i[record_type record_id name blob_id],
            name: :index_active_storage_attachments_uniqueness, unique: true

  create_table :active_storage_variant_records, force: true do |t|
    t.references :blob, null: false, index: false
    t.string     :variation_digest, null: false
  end
  add_index :active_storage_variant_records,
            %i[blob_id variation_digest],
            name: :index_active_storage_variant_records_uniqueness, unique: true
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
