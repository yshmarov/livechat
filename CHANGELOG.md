# Changelog

## 0.9.0

- **One design system across the family.** The stylesheet now opens with a
  shared core — the colour tokens, `.page-head`, `.tabs`, `.filters`, `.card`,
  `.badge`, buttons and form controls, and the `.dashboard-shell` +
  `.record-row` + `.detail-panel` two-pane dashboard — identical in all five
  gems of the family, apart from the `--lvc-` prefix. The five had drifted:
  sidebars between 380px and 430px, reading columns between 860px and 1020px,
  two different tab styles and three different button styles. The sidebar is
  now 330–430px everywhere, a reading page 1020px, a dashboard 1280px.
  Everything below the `GEM-SPECIFIC` banner is what only this gem has.
- **The inbox markup uses the shared class names.** `.inbox-shell`,
  `.inbox-sidebar` and `.inbox-thread` are `.dashboard-shell`,
  `.dashboard-sidebar` and `.dashboard-detail`; `.conversation-list`,
  `.conversation-row`, `.conversation-main`, `.conversation-topline`,
  `.conversation-meta`, `.conversation-time` and `.conversation-side` are
  `.record-*`, with `.conversation-name` becoming `.record-name` and
  `.conversation-preview` `.record-copy`; `.conversation-panel` is
  `.detail-panel` and its `.head-row` is `.panel-head`. The body class on the
  inbox is `lvc-index` (was `lvc-inbox`) and the polling element is
  `#lvc-poll` (was `#lvc-index`). A conversation row now reads name, then
  message preview, then ids — the order the sibling gems use. If you styled or
  scripted any of those names in a host app, that is the breaking change — no
  configuration, route or database change is involved.
- **The narrow-screen rules work again.** The `max-width: 760px` block sat above
  the component rules it means to override, and CSS nesting adds no specificity,
  so the desktop grid won every tie: showing one pane at a time on a phone had
  quietly stopped working. The media query moved to the end of the file.
- Smaller fixes that came with the shared core: a submit input is styled as a
  button rather than a full-width field, the filter row keeps its search box and
  button on one line, and a `code.key` truncates inside a list row instead of
  wrapping over three lines.

## 0.8.0

- **`config.agent_layout` now works on its own.** The inbox's stylesheet and
  script were declared in the gem's layout, so replacing that layout dropped
  both: unstyled inbox with its thread polling and keyboard submit dead. They
  move into the views, so every layout gets them with nothing asked of the host.
- **The dashboard stylesheet no longer claims selectors it does not own.** It
  styled bare `*`, `body` and `a`, and its `.container`, `.card` and `.tabs` are
  names other frameworks use too. Component rules now nest inside a
  `.lvc-dashboard` wrapper the views render, and every custom property is
  `--lvc-` prefixed — that collision ran both ways, so a host defining `--bg`
  recoloured the inbox just as easily.
- **Added `config.base_controller_class`.** Name the controller your own admin
  inherits from and the inbox adopts its layout, helpers, authentication and
  request context. It reparents the inbox only — the widget, visitor API and
  attachment proxy stay on the engine's public controller, so it can never
  demand a staff session from a visitor starting a chat. Default is unchanged.
- **Migrations follow the host's `primary_key_type`,** including the engine's own
  `messages -> conversations` foreign key, which has to match or a bigint column
  ends up pointing at a uuid table. A uuid-keyed app has a uuid
  `active_storage_attachments.record_id`, so bigint tables here could never hold
  a message attachment: `attach` raised `NotNullViolation`.
- **Dropped the `id: /\d+/` constraints** on the attachment and conversation
  routes, which were what forced the tables to be bigint. Ordering already
  disambiguates: every fixed-name route is declared first.
- **`t.references :conversation` no longer creates its own index.**
  `(conversation_id)` is a leftmost prefix of the `(conversation_id, id)` index
  the migration already adds, so it answered no query the wider one could not.
  Existing installs keep theirs until they drop it:
  `remove_index :livechat_messages, :conversation_id`.
- A `BackboneTest` now fails the build on any of the above regressing.

## 0.7.2

- Adds `AGENTS.md`: install and integration instructions written for coding
  agents — the request-shaped config lambdas, the two settings email needs, why
  polling is the default and Action Cable is opt-in, and the mistakes agents
  actually make. It ships inside the gem, so
  `cat "$(bundle show livechat)/AGENTS.md"` works from a host app.
- The dummy app pins `queue_adapter = :test` for the test suite. Attaching a
  file enqueues Active Storage's analysis job, and the default `:async` adapter
  runs it on a background thread with its own database connection — writes no
  test transaction covers, which is how a suite starts failing order-dependently
  in a test that never created a row. No effect on the gem itself.

## 0.7.1

- Removed the translucent border and background from the customer-facing
  avatar so app logos sit cleanly on the widget header.

## 0.7.0

- Added `config.avatar_url`, accepting a URL or per-request callable, to show
  an optional customer-facing avatar in the visitor widget header. Failed
  images disappear cleanly, and external image requests omit the referrer.
- Added `bin/rails livechat:seed_demo` for idempotent sample conversations in
  development and demo environments.

## 0.6.8

- Fixed Rails 7.1 compatibility for attachment configuration by avoiding the
  dynamic Active Storage `service:` lambda on versions that only accept a
  concrete service name.

## 0.6.7

- Added `config.agent_layout`, letting host apps render the Livechat inbox
  inside their own admin layout while keeping the standalone gem layout as the
  default.

## 0.6.6

- Expanded the desktop visitor widget into a taller, wider panel with equal
  viewport padding above and below, while preserving the existing full-screen
  mobile chat behavior.

## 0.6.5

- Added `mount_livechat at: "/livechat"` as the install-time route helper,
  keeping `config.mount_path` synchronized with the mounted engine path while
  preserving manual `mount Livechat::Engine` compatibility.
- Extracted the dashboard stylesheet into a same-origin, fingerprinted
  `/dashboard.css` endpoint and added CSP meta tags to the dashboard layout.
  The public widget remains pipeline-free and controller-served.
- Added `config.storage_service`, so host apps can route Livechat attachments
  to a named Active Storage service instead of the app default.

## 0.6.4

- Hardened the visitor widget composer against host app form-control styles, so
  embedded textareas no longer pick up an extra border or shadow.
- Matched the visitor widget's chat surface to the inbox pattern: white thread
  background, gray support bubbles, and visible timestamps.
- Fixed stale typing indicators by clearing each side's typing hint when they
  send and suppressing the hint when a new message arrives.
- Renamed the default inbox title to `LiveChat` across shipped locales while
  keeping it overridable through `livechat.dashboard.title`.
- Simplified inbox conversation context by showing visitor email as plain text,
  removing the page URL from the thread header, and keeping direct
  `/livechat/:id` pages scrollable after the two-column inbox layout.

## 0.6.3

- Replaced the selected thread's separate status badge and resolve/reopen
  button with a compact Open/Resolved status toggle.
- Refreshed the README inbox screenshots to show the new status toggle.

## 0.6.2

- Reworked the inbox into a two-column desktop layout: conversation list on the
  left, selected thread on the right, with live message polling preserved.
- Improved the conversation list with compact rows showing the visitor, last
  message preview, unread count, relative activity time, and participating
  agent avatars.
- Kept mobile as a focused single-pane inbox/thread flow.

## 0.6.1

- Repositioned the docs around in-app support messaging for Rails: users ask
  for help from the page where they got stuck, and teams answer from the
  mounted inbox without SaaS, third-party scripts, or a separate support app.
- Added `message:` to `livechat_button`, so contextual support buttons can open
  the widget and prefill the composer in one helper call.
- Updated the PRD to match the current shipped feature set through 0.6.0.

## 0.6.0

- Improved unread notification emails. Team emails now summarize the unread
  visitor burst with up to five messages, attachment names, visitor email,
  locale, page URL, and a count of any additional unread messages. Visitor
  reply emails now summarize unread agent replies the same way.
- Added lightweight typing indicators. Visitors can see when an agent is
  typing, and agents can see when the visitor is typing, using short-lived
  cache hints over the existing polling endpoints. No database migration or
  mandatory Action Cable setup required.

## 0.5.4

- Balanced the recording controls visually: the stop/finish square now uses
  the same icon box as the cancel control, so the actions read with equal
  weight in the composer.

## 0.5.3

- Refined the audio recording controls. While recording, the composer now
  shows a compact REC pill with a stable timer, an icon-only discard control,
  and an icon-only stop control. Sending is disabled until recording is
  stopped or cancelled.

## 0.5.2

- Added audio messages. Visitors can record a voice note from the widget, send
  it as an attachment, and both visitors and agents can play audio files
  inline in the conversation.
- Tightened the mobile chat modal scroll lock for iOS keyboard edge cases. The
  widget now locks both root elements, blocks touch scrolling that escapes the
  chat thread, and re-checks the lock when the viewport switches between phone
  and desktop widths while the panel is open.

## 0.5.1

- Fixed the mobile chat panel letting the page scroll behind it (and the host
  page showing through above/below the panel) while the keyboard was open.
  The scroll lock now pins `<body>` with `position: fixed` — `overflow:hidden`
  alone is ignored by iOS Safari for touch — so the background is truly frozen
  and the keyboard-pinned panel covers the visible area with no gaps.

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
