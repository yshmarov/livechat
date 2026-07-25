# PRD: livechat

> Status: v0.1 shipped 2026-07-25 — models, widget (polling), inbox,
> notifications, generator, 26 locales, CI. Not yet shipped: ActionCable
> push, participants/assignment, attachments, CSAT (see Milestones).

Drop-in support chat for Rails apps. A mountable engine that gives any Rails app a Crisp/Intercom-style chat widget and an agent inbox — data in the host app's database, no third-party service, no separate deployment.

Name: `livechat` (chosen 2026-07-25; verified free on rubygems.org). Ruby module: `Livechat`. **Push a real v0.1.0 to RubyGems as soon as the loop works — the name is only reserved once published.**

Trademark note: LiveChat® is a registered mark of a SaaS company in this category. Decision made with eyes open. Mitigations: always style the gem generically as lowercase `livechat` ("open-source live chat for Rails"), never imitate LiveChat Inc's branding, logo, or "LiveChat" camel-case styling, and keep a pre-1.0 willingness to rename if ever challenged.

## 1. Problem

Rails apps that want to talk to their users choose between paid third-party SaaS (Crisp, Intercom — $45+/mo, customer conversations on someone else's servers, third-party script on every page) or self-hosting a full platform (Chatwoot, Chaskiq — a second application to deploy, monitor, and upgrade). There is no `bundle add` option. The niche is empty as a gem.

## 2. Positioning

**Live chat when you're there, async messaging when you're not.** The widget sets honest expectations (configurable reply-time text) instead of promising an agent watching in real time. Offline is a first-class case; email notification is a core feature, presence/typing indicators are not. This keeps scope gem-sized and avoids the dead-chat-widget problem (a chat widget nobody answers is worse than no widget).

Tagline: *"livechat — open-source live chat for Rails. Your users write in your app; your team answers from your app."*

## 3. Goals

- One visitor ↔ many agents: any authorized staff member can reply in any conversation; **each message shows which agent wrote it**.
- Works for both signed-in users and anonymous visitors.
- 5-minute install: `bundle add livechat` → `rails g livechat:install` → `rails db:migrate` → `<%= livechat_tag %>`.
- Zero host dependencies: no Tailwind/Stimulus/importmap/build step; safe under strict CSP; invisible to Propshaft/Sprockets.
- All conversation data in host-app tables (`livechat_*`), no FK coupling to the host user model.

## 4. Non-goals (v1)

- Feature parity with Intercom/Chatwoot: no omnichannel (email-in, WhatsApp, Messenger), no AI bots, no campaigns, no mobile agent apps.
- Online presence and typing indicators (revisit after ActionCable phase).
- File attachments (revisit post-1.0; feedback_engine's Active Storage screenshot pattern is the template).
- Websocket push in v1 — polling first (see §8).
- Assignment/routing workflows — v1 is a shared inbox; every agent sees everything.

## 5. Personas

- **Visitor** — end user of the host app; may be signed in or anonymous. Opens the widget, writes a message, comes back later for the reply.
- **Agent** — admin/support staff of the host app. Works the inbox, replies, resolves conversations. Multiple agents collaborate in one thread.
- **Host developer** — installs and configures the gem; wires `current_user` and `authorize_agent` lambdas; wants zero surprises in their asset pipeline and CSP.

## 6. User stories

1. As a visitor, I click the launcher bubble, type a message, and see it in the thread immediately.
2. As a visitor, I see agent replies appear without reloading the page (while the panel is open).
3. As an anonymous visitor, I return the next day and still see my conversation (cookie identity).
4. As an anonymous visitor, I can leave my email so replies reach me when I'm gone.
5. As an agent, I see a list of conversations with unread badges, newest activity first, with last-message previews.
6. As an agent, I open a thread, see who wrote every message (visitor vs. named colleague), and reply.
7. As an agent, I resolve a conversation; the visitor can reopen it by writing again.
8. As an agent, I get an email when a visitor writes and nobody has replied.
9. As a host developer, I control who is an agent with one lambda, and the widget/dashboard never breaks my CSP or asset pipeline.

## 7. Data model

Two tables, string-typed author references (feedback_engine pattern — no FK to host users).

**`livechat_conversations`** — the container (hypemarket: cached list fields; ethicsportal: the container *is* the thread)

| column | type | notes |
|---|---|---|
| `visitor_token` | string, indexed, not null | random token; identity for anonymous visitors |
| `visitor_id` | string, nullable | host user id when signed in |
| `visitor_label` | string | email/name via `visitor_label` lambda |
| `visitor_email` | string, nullable | captured in-widget for anonymous visitors |
| `status` | string, default `open` | `open` / `resolved` (hand-rolled, feedback_engine style) |
| `last_message_preview` | string | denormalized via `update_columns` on message create |
| `last_activity_at` | datetime, indexed | list ordering |
| `page_url`, `locale` | string | live context — refreshed on every visitor message |

**`livechat_messages`**

| column | type | notes |
|---|---|---|
| `conversation_id` | FK, not null | indexed with `created_at` (hypemarket) |
| `author_type` | string, not null | `visitor` / `agent` / `system` (ethicsportal enum) |
| `agent_id` | string, nullable | required when `author_type == "agent"` |
| `agent_label` | string | resolved at write time — the multi-agent attribution requirement |
| `body` | text, not null | plain text v1, length-capped, rendered escaped |
| `read_at` | datetime | read tracking per side (ethicsportal) |

`system` messages record events in-thread ("Alice resolved this conversation") — ethicsportal pattern.

**Deliberate omission:** no participants join table in v1. Ethicsportal's lesson: participant rows governed *notification routing*, never posting permission — permission was always policy-based. v1 keeps reply-permission = `authorize_agent`, notifications = all agents. A `livechat_participants` table arrives with assignment/routing (post-1.0) without migration pain.

Model niceties carried over: `messages_with_headers` grouping (show author header when sender changes, message is system, or >5 min gap — hypemarket); `newest_activity_first` scope; dynamic status predicates.

## 8. Visitor widget

**Delivery** — direct reuse of the i18n-feedback/feedback_engine `Widget` class:

- `livechat_tag` helper renders a two-`<script>` snippet: a `type="application/json"` config block (data, never executed, no nonce needed, re-read on every `turbo:load`) + a nonce'd inline script with the widget JS.
- JS lives at `lib/livechat/widget.js` — **not** `app/assets/` — so host pipelines never ingest it (i18n-feedback v0.7.1 lesson).
- Styles injected at runtime via a created `<style>` element; `</` escaped in JSON; nonce from `content_security_policy_nonce`, no-op when host has no CSP; CSRF from `<meta name="csrf-token">`.
- Turbo-safe: `window.__livechatLoaded` guard, document-level listeners registered once, re-render on `turbo:load`.

**Behavior:**

- Floating launcher bubble (`show_launcher`, `launcher_label` config; any element with `data-livechat-open` also opens it).
- Panel: greeting text (`greeting`), reply-time expectation (`reply_time_text`, e.g. "We usually reply within a few hours"), message thread, textarea, send.
- Unread badge on the launcher when agent replies arrived since last open.
- Anonymous visitors are prompted (non-blocking) for an email after their first message.

**Identity:**

- Signed-in: `current_user` lambda (request → user), `visitor_label` lambda for display — identical mechanism to feedback_engine.
- Anonymous: `visitor_token` in a signed, long-lived cookie set by the engine on first message. Same-site cookie is sufficient (simpler than ethicsportal's access-code+passcode, which exists for cross-device anonymous return — out of scope v1).
- If an anonymous visitor later signs in, their token conversations can be claimed onto their user id (nice-to-have, v1.x).

**Realtime transport — polling in v1, deliberately.** The zero-dependency philosophy rules out requiring turbo-rails or the ActionCable JS client on host pages. The widget polls `GET .../messages?after=<id>` while the panel is open (~4s), backing off to ~30s when closed (stops when tab hidden). Support-chat volume makes this cheap. **v1.x:** optional push — vendor the `@rails/actioncable` client inside widget.js (~10 KB) and subscribe when the host has a cable configured (Rails 8 Solid Cable makes this default-on); polling stays as fallback. Never a hard requirement.

## 9. Agent inbox

Mounted at `/livechat` (configurable `mount_path`).

- **Routes:** `resources :conversations, only: [:index, :show]` + member `resolve`/`reopen`, nested `resources :messages, only: [:create]`; plus the public widget endpoints (create message, poll messages) gated separately.
- **Index:** open/resolved tabs with counts (`group(:status).count`), ordered by `last_activity_at`, unread badges, last-message preview, visitor label, pagination `PER_PAGE = 50` — the i18n-feedback v0.8.0 dashboard pattern, but writable.
- **Show:** thread with grouped author headers; every agent message displays `agent_label` — multiple agents in one thread are visibly distinct (core requirement). Visitor messages marked read on view (ethicsportal's `mark_messages_read!`). Reply form posts and resets.
- **Authorization:** `before_action :require_agent` everywhere except public widget endpoints; `authorize_agent` lambda, default `->(req) { Rails.env.development? }` — independent of `enabled`, exactly like i18n-feedback's `authorize_admin`, so staff can work the inbox in production even where the widget is gated.
- **Agent identity:** the replying agent resolves from the same `current_user` lambda; `agent_label` (default: email) stamps each message. `agent_display_name` lambda controls what the **visitor** sees (default: same label; hosts can return first-name-only or a generic "Support team" — ethicsportal hides handler names entirely; here visibility is the default per product requirement, privacy is the option).
- **Layout:** self-contained inline CSS, CSS custom properties, `color-scheme: light dark` — feedback_engine's layout cloned. No inline event handlers anywhere (i18n-feedback v0.8.2 CSP lesson).
- **Inbox realtime:** v1 polls the open thread (engine-controlled page, same JS approach as the widget). When ActionCable lands (v1.x), inbox threads subscribe via per-conversation streams and messages `broadcast_append_to` from `after_create_commit` — hypemarket's model-broadcast + empty-turbo-stream-response pattern.

## 10. Notifications

Two directions, hooks first, batteries optional:

- **Visitor wrote → agents.** `on_visitor_message` lambda (default noop) for hosts wiring Noticed/Slack/etc. Built-in convenience: if `agent_emails` (lambda → array) is configured, the gem's own mailer emails those addresses. Debounced: only when the message starts a new unread stretch.
- **Agent wrote → visitor.** `on_agent_message` lambda; built-in: if the conversation has `visitor_email`, send "New reply from {agent_display_name}" with a link back to `page_url`. This is what makes the async half credible.
- Mailer uses host's ActionMailer config; `mailer_from` config; all templates I18n-resolved with English fallbacks.

## 11. Configuration

`Livechat.configure` block, PORO config with defaulted `attr_accessor`s, memoized singleton (feedback_engine pattern). Request-dependent options are lambdas receiving the Rack request.

| option | default | purpose |
|---|---|---|
| `enabled` | `->(req) { true }` | gates widget + public endpoints |
| `authorize_agent` | `->(req) { Rails.env.development? }` | gates inbox |
| `current_user` | `->(req) {}` | resolve user (needs `#id`) |
| `visitor_label` | email-or-to_s lambda | visitor display label |
| `agent_label` | email-or-to_s lambda | attribution stored on message |
| `agent_display_name` | `->(label) { label }` | what visitors see |
| `agent_emails` | `nil` | enable built-in agent notification mail |
| `mailer_from` | `nil` | built-in mailer sender |
| `greeting` / `reply_time_text` / `launcher_label` | localized defaults | widget copy |
| `show_launcher` | `true` | floating bubble vs. `data-livechat-open` only |
| `mount_path` | `"/livechat"` | must match routes mount |
| `rate_limit` | `{ to: 30, within: 60 }` | Rails 7.2+ `rate_limit`, no-op on 7.1 |
| `on_visitor_message` / `on_agent_message` | noop | host hooks |

Initializer template ships every option commented with Devise examples (existing convention).

## 12. i18n, security, privacy

- Locale files `config/locales/livechat.<locale>.yml`, launch with the same 26 languages; every string via `I18n.t(scope: :livechat, default: <English>)`; RTL flag in widget config; locale-parity test.
- Message bodies: plain text, length-capped (~5,000 chars), always HTML-escaped. No markdown v1 (XSS surface).
- Rate limiting on public endpoints; visitor endpoints scoped strictly by signed cookie token — no enumerable conversation ids (UUID/obfuscated public ids).
- Data retention: `Livechat::Conversation.purge_resolved(older_than:)` documented for host cron; no automatic deletion.
- No data leaves the host app, period — that's the product.

## 13. Engine structure, install, testing, release

Clone the proven skeleton:

- `isolate_namespace Livechat`; helper included via `ActiveSupport.on_load(:action_view)`; gemspec: runtime dep `rails >= 7.1` only, Ruby `>= 3.2`, MFA required, trusted-publishing release workflow on `v*` tags.
- Install generator: initializer copy + `migration_template` × 2 + route `mount Livechat::Engine => "/livechat"` + post-install `say` (migrate → add `<%= livechat_tag %>` before `</body>` → visit `/livechat`).
- Testing: **Minitest** + `test/dummy` app (with fixed-nonce CSP for asserting nonce'd scripts — i18n-feedback trick), schema loaded in `test_helper`, config reset in setup/teardown. Model tests (`ActiveSupport::TestCase`), integration tests for widget endpoints + inbox authorization (`ActionDispatch::IntegrationTest`), system tests via `ApplicationSystemTestCase` + Capybara headless Chrome covering the full loop (widget open → send → appears in inbox → reply → appears in widget via poll). Run with `bin/rails test` / `rake test`. No RSpec.
- CI matrix Ruby 3.2–3.4 × Rails 7.1–8.1 via `gemfiles/`; RuboCop; Keep-a-Changelog CHANGELOG; commit convention `<summary> (vX.Y.Z)`.

## 14. Milestones

- **v0.1 — the loop works.** Models, widget (open/send/poll), inbox (index/show/reply), agent attribution, anonymous cookie identity, CSP-safe snippet, install generator. **Ship to RubyGems immediately to secure the name.**
- **v0.2 — inbox quality.** Unread badges + read tracking, resolve/reopen + system messages, message grouping headers, launcher unread badge, search.
- **v0.3 — async credible.** Built-in mailers both directions, visitor email capture, `on_*` hooks.
- **v0.4 — polish.** 26 locales + RTL, dark mode audit, rate limiting hardening, purge API. → **v1.0** = v0.4 stabilized.
- **Post-1.0:** ActionCable push (vendored client, polling fallback), participants + assignment + smarter notification routing, typing indicator, attachments, claim-anonymous-conversations-on-login, visitor CSAT rating.

## 15. Risks / open questions

- **Trademark** — see the note at the top; accepted with mitigations (generic lowercase styling, no branding imitation, pre-1.0 rename willingness).
- **Unanswered chats** — mitigated by honest reply-time copy + agent email notifications, but ultimately a host-behavior risk; docs should say so.
- **Polling cost** on very-high-traffic pages: poll only while panel open/visible; ActionCable phase removes it.
- **Spam** on the anonymous endpoint: rate limit + honeypot; captcha stays out (no third-party calls, on principle).
- **Open question:** built-in agent-notification email per-message or digest? Lean: immediate for the first unread message per conversation, then silent until an agent reads.

## 16. Success criteria

- Fresh Rails 8 app → working chat in under 5 minutes without touching JS/CSS.
- Widget functions under a strict nonce-based CSP with zero console violations.
- Host asset pipeline (Propshaft or Sprockets) never sees the gem.
- A conversation with two different agents replying shows correct, distinct attribution in both inbox and widget.
- CI green across the full Ruby × Rails matrix.
