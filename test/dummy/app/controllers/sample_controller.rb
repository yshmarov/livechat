# frozen_string_literal: true

class SampleController < ActionController::Base
  # A host page carrying the widget, like any layout that renders livechat_tag.
  def show
    render inline: <<~ERB
      <!DOCTYPE html>
      <html>
        <head><%= csrf_meta_tags %></head>
        <body>
          <h1>Sample page</h1>
          <a href="#" id="custom-opener" data-livechat-open>Chat</a>
          <a href="#" id="styled-opener" data-livechat-open data-livechat-badge-class="host-badge">Help</a>
          <%= livechat_button(class: "btn") %>
          <%= livechat_button("Ask about order", message: "I need help with order #123") %>
          <%= livechat_tag %>
        </body>
      </html>
    ERB
  end

  # A host page of its own with the chat in it (livechat_chat), under a tall
  # page so a test can tell the page still scrolls.
  def support
    render inline: <<~ERB
      <!DOCTYPE html>
      <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <%= csrf_meta_tags %>
        </head>
        <body>
          <h1>Support</h1>
          <a href="#" id="custom-opener" data-livechat-open data-livechat-message="About my invoice">Ask</a>
          <%= livechat_chat id: "host-chat", style: "height: 500px" %>
          <div style="height: 2000px">Footer</div>
          <%= livechat_tag %>
        </body>
      </html>
    ERB
  end
end
