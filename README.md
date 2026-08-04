# livechat

[![Gem Version](https://img.shields.io/gem/v/livechat)](https://rubygems.org/gems/livechat)
[![Downloads](https://img.shields.io/gem/dt/livechat)](https://rubygems.org/gems/livechat)
[![CI](https://github.com/yshmarov/livechat/actions/workflows/ci.yml/badge.svg)](https://github.com/yshmarov/livechat/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](MIT-LICENSE)

**In-app support messaging for Rails.** Add a chat button so users can ask for
help from the page where they got stuck. Your team answers from a mounted inbox.
No SaaS account, no third-party script, no separate app, no customer data leaving
your database.

Use it when email is too detached, Intercom is too much, and Chatwoot is another
app you do not want to deploy.

![The livechat widget open over a running Rails app](docs/screenshots/01-widget.png)

## Install

```ruby
# Gemfile
gem "livechat"
```

```bash
bundle install
bin/rails generate livechat:install
bin/rails db:migrate
```

```erb
<%# app/views/layouts/application.html.erb %>
<%= livechat_tag %>
```

That's it. Visit any page, click the bubble, say hi. Answer yourself at
`/livechat`.

Optional demo data:

```bash
bin/rails livechat:seed_demo
```

It creates two idempotent sample conversations: one open thread with an unread
visitor reply, and one resolved thread. Running the task again refreshes those
demo messages instead of duplicating conversations.

> [!IMPORTANT]
> The inbox defaults to **development only**. Set `authorize_agent` before you
> deploy — see [Configure](#configure).

Ruby >= 3.2 · Rails >= 7.1 · Active Storage only if you want file attachments.

Installing with a coding agent? Point it at [AGENTS.md](AGENTS.md) — the same
steps in the order an agent needs them, plus the gates it tends to get wrong and
the things it should not do. It ships inside the gem, so
`cat "$(bundle show livechat)/AGENTS.md"` works from any app that bundles it.

## What you get

|               |                                                                          |
| ------------- | ------------------------------------------------------------------------ |
| **Widget**    | Chat bubble, expandable panel, drafts preserved, unread badges            |
| **Inbox**     | Open / resolved tabs, search across everything, who-worked-what column    |
| **Team**      | Any teammate answers any thread; every reply signed with its author       |
| **Email**     | Both directions — one per unread stretch, not one per message             |
| **Files**     | Images inline, documents as links. Served through the engine, never a blob URL |
| **Realtime**  | Polling by default (no Redis, no Action Cable). Push is opt-in            |
| **Threads**   | One per visitor — a conversation, not tickets. Writing again reopens it   |
| **Deps**      | None. Plain JS — no Tailwind, no Stimulus, no importmap, no build step    |
| **Auth**      | Lambdas over the raw request — Devise, Rails 8 auth, anything             |
| **i18n**      | 26 languages, RTL included                                               |
| **Turbo/CSP** | Turbo Drive and strict nonce-based CSP out of the box                     |

## Why a gem

|                        | `livechat`                     | Hosted chat SaaS            |
| ---------------------- | ------------------------------ | --------------------------- |
| Cost                   | Free, MIT                      | Per-seat, per-month         |
| Where conversations live | Your database                | The vendor's                |
| To deploy              | `bundle add livechat`          | A script tag, or a second app |
| Visitor identity       | Server-side, from your session | Whatever the visitor types  |
| Page weight            | One `<script>`, no CDN         | Third-party bundle          |
| Infrastructure         | None. Polling by default       | Theirs, or your own Redis + Cable |
| "Powered by" badge     | Never                          | Usually, until you pay      |

## How it works

1. Add `<%= livechat_tag %>` to your layout. A bubble appears bottom-right —
   or open the panel from any element with `data-livechat-open`, or
   `window.Livechat.open()`.
2. A visitor writes. The message lands in `livechat_conversations` in your
   database, and — if you configured it — in your team's email.
3. Your team answers at `/livechat`. Several people can work the same thread;
   resolve it when done. A visitor writing again reopens it.
4. The visitor sees the reply in the widget, or by email when they're gone.

**Realtime is polling, on purpose:** ~4s while the panel is open, ~30s in the
background, nothing at all for visitors who never wrote. No Action Cable, no
Redis, no infrastructure. At support-chat volume you will not notice; your ops
person will notice there is nothing new to run. Already running Action Cable
and want instant delivery? `config.action_cable = true` — polling stays the
fallback.

## The inbox

Open and resolved filters, unread badges, search (visitor name, email, and
everything anyone wrote), and a two-column desktop layout with the chat list on
the left and the selected thread on the right. Reply with Cmd/Ctrl+Enter,
resolve, reopen. The inbox keeps itself fresh while you watch — and never
reloads over a half-written reply or search.

| Desktop inbox | Mobile thread |
| --- | --- |
| ![The inbox: conversation list on the left and selected thread on the right](docs/screenshots/03-inbox.png) | ![The mobile thread view with reply composer](docs/screenshots/04-conversation.png) |

Every reply carries its author and time, and resolving is recorded in the
thread. Gated by `authorize_agent`.

## Configure

Everything is optional — a fresh install works with zero config. In
`config/initializers/livechat.rb`:

| Option | Default | What it does |
| --- | --- | --- |
| `authorize_agent` | development only | **Who can read the inbox.** Override before deploying |
| `enabled` | everyone | Who sees the widget. `false` hides it and rejects posts |
| `current_user` | `nil` | Identify the visitor. Receives the request |
| `app_name` | Rails app name | Shown in the widget header |
| `greeting` | localized default | First message visitors see |
| `reply_time_text` | localized default | "We usually reply within a few hours" |
| `launcher_label` | localized default | Text on the bubble |
| `avatar_url` | `nil` | Customer-facing avatar in the widget header; URL or per-request callable |
| `accent_color` | `nil` | One hex restyles launcher, header, bubbles, send button |
| `show_launcher` | `true` | `false` hides the bubble — bring your own entry point |
| `visitor_label` | name, else email | How a visitor is labelled in the inbox |
| `agent_label` | name, else email | How an agent is labelled internally |
| `agent_display_name` | the full label | What **visitors** see — trim it or anonymise it |
| `mailer_from` | `nil` | Required for any email |
| `agent_emails` | `nil` | Who gets notified of new visitor messages |
| `on_visitor_message` | no-op | Runs after a visitor writes — Slack, etc. |
| `on_agent_message` | no-op | Runs after an agent replies |
| `attach_files` | `true` | File attachments (needs Active Storage) |
| `storage_service` | `nil` | Named Active Storage service for chat attachments |
| `max_attachments` | `5` | Per message |
| `max_attachment_size` | `10.megabytes` | Enforced server-side |
| `allowed_attachment_types` | `nil` (any) | Or an allowlist, e.g. `%w[image/png application/pdf]` |
| `action_cable` | `false` | Opt into push delivery |
| `action_cable_url` | `"/cable"` | Match your `mount ActionCable...` |
| `rate_limit` | `{ to: 30, within: 1.minute }` | Per-IP throttle (Rails 7.2+). `nil` disables |
| `mount_path` | `"/livechat"` | Keep in sync with `mount` in `routes.rb` |

A typical initializer:

```ruby
Livechat.configure do |config|
  config.current_user     = ->(request) { request.env["warden"]&.user }
  config.authorize_agent  = ->(request) { request.env["warden"]&.user&.admin? }
  config.mailer_from      = "chat@example.com"
  config.agent_emails     = -> { User.where(admin: true).pluck(:email) }
  config.reply_time_text  = "We usually reply within an hour."
  config.avatar_url       = "/support-avatar.png"
  config.accent_color     = "#7c3aed"
end
```

`avatar_url` can also choose branding from the current request:

```ruby
config.avatar_url = ->(request) { request.env["current_account"]&.support_avatar_url }
```

Prefer a same-origin image. If the URL uses another host, allow that host in
your application's `img-src` Content Security Policy.

Gates receive the **raw request**, so they work with any auth:

```ruby
# Devise / Warden
config.current_user = ->(request) { request.env["warden"]&.user }

# Rails 8 built-in auth (bin/rails generate authentication)
config.current_user = lambda do |request|
  token = request.cookies["session_token"]
  Session.find_signed(token)&.user if token
end
```

<details>
<summary><b>Who visitors talk to</b></summary>

Replies are signed. What visitors see is up to you:

```ruby
config.agent_display_name = ->(label) { label.split.first }   # "Ada"
config.agent_display_name = ->(_label) { "Support team" }     # anonymous
```

</details>

<details>
<summary><b>Email, both directions</b></summary>

When a visitor writes and nobody has read it, the team gets one email — one per
unread stretch, not one per message. When an agent replies and the visitor is
away, the visitor gets one email (signed-in visitors automatically, guests once
they leave an address — the widget asks, gently).

Requires `mailer_from`; team notifications also need `agent_emails`. For
anything else, hook in:

```ruby
config.on_visitor_message = ->(message) { SlackNotifier.ping(message) }
```

</details>

<details>
<summary><b>File attachments</b></summary>

On by default wherever the app has Active Storage. If you don't already:

```bash
bin/rails active_storage:install && bin/rails db:migrate
```

Visitors get a paperclip in the composer; agents get a file field on the reply
form. Images render inline, other files as download links. Every file is served
through the engine's own route and gated the same way the chat is — an agent,
or the visitor who owns that conversation — so nothing leaks through a
guessable or long-lived blob URL.

Where Active Storage isn't installed, the widget quietly stays text-only.

Set `config.storage_service` to route chat uploads to a dedicated Active
Storage service from your app's `config/storage.yml`:

```ruby
config.storage_service = :livechat_uploads
```

</details>

<details>
<summary><b>Realtime with Action Cable</b></summary>

Polling is the default and needs nothing from your app. If you already run
Action Cable, turn on push so a reply appears the instant it's sent:

```ruby
config.action_cable = true
config.action_cable_url = "/cable" # match your `mount ActionCable... => ...`
```

A new message nudges the widget and the inbox to refresh at once; polling stays
the fallback, so a dropped socket or a proxy that blocks WebSockets never means
a missed message. The widget speaks the Action Cable protocol over a plain
WebSocket — no `@rails/actioncable`, no build step — and only ever subscribes
to a stream the server signed for it. Under a strict CSP, allow the socket with
`connect-src 'self'`.

</details>

## Widget API

| | |
| --- | --- |
| `window.Livechat.open()` / `.close()` | `open("Hi, I need help with…")` prefills the box — never over a visitor's draft |
| `data-livechat-open` | Any element opens the panel on click |
| `data-livechat-message="…"` | Prefill from that element — great for contextual buttons |
| `<%= livechat_button %>` | A plain, unstyled opener button |
| `<%= livechat_button("Ask about this order", message: "I need help with order ##{@order.id}") %>` | Open and prefill in one helper |
| `config.show_launcher = false` | Hide the bubble entirely |

While replies are unread, every `data-livechat-open` element carries a small
count badge — so hiding the launcher never hides the answer.

Contextual buttons are where a Rails app beats a generic support widget:

```erb
<%= livechat_button("Ask about this order",
      message: "I need help with order ##{@order.id}") %>

<%= livechat_button("Ask about this invoice",
      message: "I need help with invoice ##{@invoice.number}") %>

<button data-livechat-open
        data-livechat-message="I need help with project <%= @project.name %>">
  Contact support
</button>
```

## Use cases

- SaaS apps: answer billing, onboarding and account questions from inside the app.
- Customer portals: let users ask about orders, invoices, documents or bookings.
- Marketplaces: keep buyer, seller and admin support tied to the current page.
- Internal tools: give non-technical teammates a direct line from admin screens.
- Course and member apps: handle access, lesson and subscription questions in context.

## What it doesn't do

No AI bots, no canned responses, no omnichannel (WhatsApp, Messenger…), no
visitor tracking, no "powered by" badge. If you need a support platform,
[Chatwoot](https://github.com/chatwoot/chatwoot) is excellent. If you need your
users to be able to reach you from inside your Rails app — this is a gem's
worth of exactly that.

## Development

```bash
bundle exec rake test
bundle exec rubocop
```

## Also by the same author

- [testimonials](https://github.com/yshmarov/testimonials) — testimonials,
  reviews and NPS for Rails.
- [ideasbugs](https://github.com/yshmarov/ideasbugs) — in-app bug reports and
  feature requests.
- [i18n_proofreading](https://github.com/yshmarov/i18n_proofreading) — in-context
  translation proofreading.
- [SupeRails](https://superails.com) — Rails screencasts.

## License

MIT.
