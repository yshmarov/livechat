# frozen_string_literal: true

module Livechat
  module InboxHelper
    # Agents have no avatar images (no FK to host users) — initials in a
    # deterministically colored circle do the job: same label, same color,
    # every page load. Full label rides the title tooltip.
    AVATAR_COLORS = 6

    def livechat_agent_avatar(label)
      initials = label.to_s.split.first(2).map { |word| word[0] }.join.upcase
      initials = label.to_s.first(2).upcase if initials.blank?
      color = label.to_s.each_byte.sum % AVATAR_COLORS

      tag.span(initials, class: "avatar color-#{color}", title: label)
    end

    # A message's attachments, rendered like the widget: images inline as
    # thumbnails, everything else as a download link. Both point at the gated
    # engine route, never a public blob URL.
    def livechat_message_attachments(message)
      attachments = message.attachments_json
      return if attachments.empty?

      tag.div(class: 'atts') do
        safe_join(attachments.map { |attachment| livechat_attachment_link(attachment) })
      end
    end

    # data-* attributes that hand dashboard.js a signed cable stream to watch,
    # or {} when push is off. Merge into the element that already polls, so a
    # nudge just fires its existing refresh sooner.
    def livechat_cable_data(stream_name)
      return {} unless Livechat.action_cable_enabled?

      { 'cable-url' => Livechat.config.action_cable_url,
        'cable-stream' => Livechat.sign_stream(stream_name) }
    end

    def livechat_attachment_link(attachment)
      if attachment[:image]
        link_to image_tag(attachment[:url], alt: attachment[:name], loading: 'lazy'),
                attachment[:url], target: '_blank', rel: 'noopener', class: 'att-img'
      else
        link_to attachment[:name], attachment[:url],
                target: '_blank', rel: 'noopener', class: 'att-file'
      end
    end
  end
end
