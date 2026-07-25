# frozen_string_literal: true

require 'test_helper'

module Livechat
  class StreamChannelTest < ActionCable::Channel::TestCase
    tests Livechat::StreamChannel

    test 'subscribes to a validly signed livechat stream' do
      subscribe signed_stream: Livechat.sign_stream('livechat:conversation:5')

      assert subscription.confirmed?
      assert_has_stream 'livechat:conversation:5'
    end

    test 'subscribes to the inbox stream' do
      subscribe signed_stream: Livechat.sign_stream('livechat:inbox')

      assert subscription.confirmed?
      assert_has_stream 'livechat:inbox'
    end

    test 'rejects an unsigned stream token' do
      subscribe signed_stream: 'not-a-real-token'
      assert subscription.rejected?
    end

    test 'rejects a missing token' do
      subscribe
      assert subscription.rejected?
    end

    test 'rejects a validly signed stream that is not a livechat stream' do
      # A signature the verifier accepts, but for a name outside our namespace —
      # a subscriber must not be able to listen anywhere just by holding a token.
      subscribe signed_stream: Livechat.stream_verifier.generate('secret:admin')
      assert subscription.rejected?
    end
  end
end
