# frozen_string_literal: true

require 'test_helper'

class ChatPageSystemTest < ApplicationSystemTestCase
  setup { Livechat.config.attach_files = false }

  test 'the chat as a page: write, read the reply, and leave no popover behind' do
    visit '/livechat/chat'

    assert_selector '[data-livechat-chat] #lvc-panel'
    assert_no_selector '#lvc-launcher'
    assert_no_selector '#lvc-close'
    assert_no_selector '#lvc-expand'

    within '#lvc-panel' do
      fill_in 'Write a message…', with: 'Writing from the chat page.'
      click_button 'Send'
      assert_selector '.lvc-msg.lvc-visitor', text: 'Writing from the chat page.'
    end

    conversation = Livechat::Conversation.last
    assert_nil conversation.page_url, 'the chat page is not where they got stuck'

    conversation.post_agent_message!(body: 'Got it, looking now.', agent_id: '1', agent_label: 'Ada')
    visit '/livechat/chat'
    within('#lvc-panel') { assert_selector '.lvc-msg.lvc-agent', text: 'Got it, looking now.' }

    visit '/sample'
    assert_selector '#lvc-launcher'
    assert_no_selector '#lvc-panel'
  end

  test 'the panel opens the same conversation as a page, in its language' do
    visit '/sample'
    find('#lvc-launcher').click
    within '#lvc-panel' do
      fill_in 'Write a message…', with: 'Started in the popover.'
      click_button 'Send'
      assert_selector '.lvc-msg.lvc-visitor', text: 'Started in the popover.'
    end

    find('#lvc-open-page').click
    assert_current_path '/livechat/chat?locale=en'
    within('#lvc-panel') { assert_selector '.lvc-msg.lvc-visitor', text: 'Started in the popover.' }

    # The chat moved to the page; the popover doesn't spring open again.
    visit '/sample'
    assert_selector '#lvc-launcher'
    assert_no_selector '#lvc-panel'
  end

  test 'a host page with the chat in it keeps scrolling on a phone' do
    # Headless Chrome won't size a window below ~500px, which is wider than the
    # widget's 480px phone breakpoint; emulate the device instead.
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride',
                                    width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit '/support'
    assert page.evaluate_script("window.matchMedia('(max-width: 480px)').matches"), 'not at phone width'

    assert_selector '#host-chat #lvc-panel'
    assert_no_selector '#lvc-launcher'

    find('#custom-opener').click
    assert_equal 'About my invoice', find('#lvc-input').value

    assert_equal '', page.evaluate_script('document.body.style.position')
    page.execute_script('window.scrollTo(0, 1000)')
    assert_operator page.evaluate_script('window.scrollY'), :>, 0
  ensure
    page.driver.browser.execute_cdp('Emulation.clearDeviceMetricsOverride')
  end
end
