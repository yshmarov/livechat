# frozen_string_literal: true

require 'test_helper'

class SeedsTest < ActiveSupport::TestCase
  test 'loads idempotent demo conversations with messages' do
    first = Livechat::Seeds.load!
    first_message_ids = Livechat::Message.order(:id).pluck(:id)
    second = Livechat::Seeds.load!

    assert_equal 2, first.size
    assert_equal first.map(&:id), second.map(&:id)
    assert_equal 2, Livechat::Conversation.where("visitor_token LIKE 'livechat-demo-%'").count
    assert_equal 6, Livechat::Message.count
    refute_equal first_message_ids, Livechat::Message.order(:id).pluck(:id)
    assert_equal %w[open resolved], second.map(&:status).sort
    assert_equal 1, second.find(&:open?).unread_from_visitor_count
  end
end
