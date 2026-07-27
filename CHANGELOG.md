# Changelog

## 0.5.0

- The full-screen mobile panel now survives the on-screen keyboard. On phones
  the panel is a fixed `100dvh` box, and iOS Safari draws the keyboard over it
  without resizing it — so the composer and send button ended up hidden behind
  the keyboard with a big empty gap above. The widget now pins the open panel
  to the `visualViewport` (the area left visible above the keyboard), shrinking
  its height and following the viewport offset so the composer sits just above
  the keyboard and the newest message stays in view. Desktop popover behaviour
  is unchanged (the pinning only runs while the mobile full-screen media query
  matches), and browsers without the `visualViewport` API simply keep the old
  CSS behaviour.
- The desktop-only expand/collapse control is now actually hidden on phones,
  where the panel is already full-screen. (The mobile rule existed but lost on
  specificity to the base button style, so the button was still showing.)

## 0.4.8

- A conversation with image attachments now opens scrolled to the bottom, not
  mid-thread. Images load after the initial scroll and grow the thread, so both
  the inbox and the widget now re-pin to the bottom as each image loads (and
  the inbox keeps you pinned until you scroll up). Fixes threads with
  screenshots opening somewhere in the middle.

## 0.4.7

- The inbox reply composer now matches the visitor widget: one bordered box
  with the reply on top and a toolbar row (paperclip left, circular send
  right) inside it, lit on focus — instead of a textarea flanked by loose
  buttons. The reply field auto-grows as you type, and file chips ride inside
  the box.

## 0.4.6

- Inbox conversation page no longer scrolls the whole page. It now fills the
  viewport with the message thread as the only scrolling region and the reply
  composer pinned at the bottom — so sending a reply keeps you at the newest
  message instead of jumping the page up to the redirect anchor. (A real
  chat-app layout, matching the visitor widget.)

## 0.4.5

- The widget's injected stylesheet now refreshes itself when its content
  changes, instead of being injected once and never replaced. Turbo keeps
  `<head>` across visits, so a tab that moved from an old widget build to a new
  one (after you ship an update) could keep the stale `<style>` and show new
  markup with old CSS until a full reload — now the styles are as
  self-freshening as the fingerprinted script URL. (Fixes 0.4.4's composer and
  header CSS not taking effect until a hard reload.)

## 0.4.4

- Expand / collapse the chat on desktop. A new header control grows the panel
  to a roomier size (and back) for long threads and image-heavy chats; the
  choice is remembered across Turbo visits. Hidden on phones, where the panel
  is already full-screen. Translated across all 26 locales.
- Composer polish: dropped the doubled focus ring (one quiet accent border
  now), and flattened Safari's default textarea bevel that showed as a second
  box inside the composer.
- Fixed a message bubble bleeding over the header's bottom edge while scrolling
  a long thread (a flexbox scroll-containment + stacking fix).

## 0.4.3

- Unified composer. The message box, attach button and send button are now one
  bordered container (the textarea on top, a toolbar row with the tools on the
  left and a circular send on the right) that lights up on focus — instead of a
  textarea flanked by loose buttons. Reads as a single control, closer to what
  people expect from a chat composer. Pending-file chips ride inside the box.

## 0.4.2

- Breathing room between the widget's pending-file chips and the composer —
  the chip row now has bottom padding, so it no longer sits flush against the
  message input.

## 0.4.1

- Consistent attachment UI across both sides. The inbox reply now shows the
  same quiet paperclip + file chips (with per-file remove) as the visitor
  widget, instead of the browser's raw "Choose Files" control — progressively
  enhanced, so the native input still works without JavaScript. Also fixed the
  widget's attach button rendering as a solid-blue second button (a CSS
  specificity slip); it's now a quiet paperclip, with the accent reserved for
  Send.

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
