# Changelog

## 0.3.0

- Inbox search: visitor name, email, and full message text, scoped to the
  current tab.
- The conversation list keeps itself fresh (new messages, new threads,
  resolves) — without ever reloading over a search in progress.
- An Agents column on the list shows which teammates have worked each thread.

## 0.2.1

- With `show_launcher = false` the panel now sits in the corner instead of
  hovering 66px above a launcher bubble that isn't there.

## 0.2.0

- Unread count badges on `data-livechat-open` elements, so launcher-less
  setups (`show_launcher = false`) still surface waiting replies.
- Message prefill: `data-livechat-message="…"` on any opener, or
  `window.Livechat.open("…")` — seeds the message box for contextual asks,
  never overwriting a visitor's draft.

## 0.1.0

- Initial release: floating chat widget (guests + signed-in visitors, one
  thread per visitor, email capture), team inbox with signed replies,
  resolve/reopen with system messages, unread tracking on both sides,
  polling transport (no Action Cable required), built-in notification
  emails in both directions (one per unread stretch), `on_visitor_message` /
  `on_agent_message` hooks, per-IP rate limiting, 26 languages, RTL, strict
  CSP support.
