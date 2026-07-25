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
          <%= livechat_button(class: "btn") %>
          <%= livechat_tag %>
        </body>
      </html>
    ERB
  end
end
