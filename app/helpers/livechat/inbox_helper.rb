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
  end
end
