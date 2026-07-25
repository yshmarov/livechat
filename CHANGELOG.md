# Changelog

## 0.4.0

- **File attachments.** Visitors and agents can attach images and documents to
  a message — a paperclip in the widget composer, a file field on the inbox
  reply. Images render inline in the thread; other files show as download
  links. Every file is served through the engine's own gated route (agent, or
  the visitor who owns the conversation) and streamed inline — never a public,
  long-lived Active Storage URL. A message can carry files with no text.
  On by default wherever the host has Active Storage; where it's absent the
  widget quietly stays text-only. Tunable: `attach_files`, `max_attachments`,
  `max_attachment_size`, `allowed_attachment_types`.
- **Optional Action Cable push.** Off by default — polling remains the
  transport and needs nothing from your app. Turn on `config.action_cable` and
  a new message nudges the widget and the inbox to refresh the instant it's
  sent, with polling still the fallback (a dropped socket never means a missed
  message). The widget speaks the Action Cable protocol over a plain
  WebSocket — no `@rails/actioncable`, no build step — and only ever subscribes
  to a per-conversation stream the server cryptographically signed for it, so
  no one can listen to a thread they weren't shown.
- New attachment strings translated across all 26 shipped locales.

## 0.3.6

- The opening greeting is now styled as a support message bubble (with a
  generic "Support" label) instead of a muted line, so the panel reads like
  a warmly-opened conversation. Deliberately generic — no fake individual,
  avatar, or presence — and still client-only (never stored, never in the
  agent inbox).

## 0.3.5

- The inbox thread now appends new messages live instead of showing a
  "New messages — refresh" link — no page reload, so an agent's half-written
  reply is never lost, and scroll position is kept unless you're at the
  bottom. Visitor messages are marked read as they stream in. Still polling
  (no Action Cable), still draft-safe.

## 0.3.4

- Docs: show how to wire `current_user` with Rails 8's built-in authentication
  (`bin/rails generate authentication`), alongside the existing Devise/Warden
  example — in the README and the generated initializer.

## 0.3.3

- Accessibility: on phones (where the panel is a full-screen modal) focus is
  trapped inside it and page scroll is locked behind it; closing restores
  focus to whatever opened the chat. Errors and the email-saved note are now
  announced to screen readers. The desktop popover deliberately stays
  non-modal — you can read the page while chatting.

## 0.3.2

- The chat panel is full-screen on phones (≤480px) — a conversation is an
  app screen, not a floating card. Inputs are 16px on mobile so iOS Safari
  never zoom-jumps on focus; the composer respects the home-indicator safe
  area; thread scrolling no longer rubber-bands the page behind it.

## 0.3.1

- The Agents column shows initials avatars (deterministic colors, full name
  on hover) instead of a comma-joined list.

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
