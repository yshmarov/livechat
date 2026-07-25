# livechat

[![Gem Version](https://img.shields.io/gem/v/livechat)](https://rubygems.org/gems/livechat)
[![CI](https://github.com/yshmarov/livechat/actions/workflows/ci.yml/badge.svg)](https://github.com/yshmarov/livechat/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](MIT-LICENSE)

Open-source live chat for Rails. Self-hosted alternative to Crisp, Intercom
and Chatwoot — as a gem, not another service to deploy.

Your users already have questions. `livechat` gives them a chat bubble and
gives you an inbox, inside the app you already run. Visitors write — signed
in or not. Your team answers — together, every reply signed with its author.
Nobody is around? Visitors leave an email and the conversation continues
there. Every word stays in your database.

- **A gem, not a platform.** `bundle add livechat`, one migration, one line
  in your layout. No second app to deploy, no third-party script on your
  pages, no per-seat pricing. Ever.
- **Zero UI dependencies.** The widget is plain JavaScript and styles itself.
  No Tailwind, no Stimulus, no importmap, no build step, no websockets to
  configure. Works with Turbo Drive and strict nonce-based CSPs out of the box.
- **Honest about response time.** The widget says "We usually reply within a
  few hours" (you choose the words), not a fake "we're online". Email
  notifications — both directions — keep slow conversations alive.
- **A team sport.** Any authorized teammate answers any thread; each message
  carries its author. You decide what visitors see — full names, first
  names, or an anonymous "Support team".
- **Real attribution.** Signed-in visitors are identified server-side against
  your user records and keep their thread across devices. Guests get a
  cookie, and keep their history when they sign up.
- **26 languages.** The widget follows your app's locale, RTL included.

## How it works

1. Add `<%= livechat_tag %>` to your layout. A chat bubble appears
   bottom-right (or open the panel from any element with
   `data-livechat-open`, or `window.Livechat.open()`).
2. A visitor writes. The message lands in `livechat_conversations` in your
   database, and — if you configured it — in your team's email.
3. Your team answers at the mount path (`/livechat`). Several people can
   work the same thread; resolve it when done. A visitor writing again
   reopens it — one thread per visitor, like a conversation, not tickets.
4. The visitor sees the reply in the widget, or by email when they're gone.

Realtime is polling, on purpose: ~4s while the panel is open, ~30s in the
background, nothing at all for visitors who never wrote. No Action Cable,
no Redis, no infrastructure. At support-chat volume you will not notice;
your ops person will notice there is nothing new to run.

## Requirements

- Ruby >= 3.2
- Rails >= 7.1

## Installation

```ruby
# Gemfile
gem "livechat"
```

```bash
bundle install
bin/rails generate livechat:install
bin/rails db:migrate
```

The generator writes `config/initializers/livechat.rb`, creates the
migration, and mounts the engine at `/livechat`. Then add the widget to your
layout:

```erb
<%= livechat_tag %>
```

That's it. Visit any page, click the bubble, say hi. Answer yourself at
`/livechat`.

## Configuration

Everything lives in `config/initializers/livechat.rb`; every option has a
working default. The essentials:

```ruby
Livechat.configure do |config|
  config.current_user = ->(request) { request.env["warden"]&.user }
  config.authorize_agent = ->(request) { request.env["warden"]&.user&.admin? }
  config.mailer_from = "chat@example.com"
  config.agent_emails = -> { User.where(admin: true).pluck(:email) }
  config.reply_time_text = "We usually reply within an hour."
end
```

### Brand color

```ruby
config.accent_color = "#7c3aed"
```

One hex value restyles the launcher, header, visitor bubbles and send
button; the widget picks black or white text automatically for contrast,
in light and dark mode alike.

### Who visitors talk to

Replies are signed. What visitors see is up to you:

```ruby
config.agent_display_name = ->(label) { label.split.first }   # "Ada"
config.agent_display_name = ->(_label) { "Support team" }     # anonymous
```

### Email, both directions

When a visitor writes and nobody has read it, the team gets one email — one
per unread stretch, not one per message. When an agent replies and the
visitor is away, the visitor gets one email (signed-in visitors
automatically, guests once they leave an address — the widget asks, gently).
Requires `config.mailer_from`; team notifications also need
`config.agent_emails`.

For anything else, hook in:

```ruby
config.on_visitor_message = ->(message) { SlackNotifier.ping(message) }
```

## The inbox

Browse at the mount path: open and resolved tabs, unread badges, search
(visitor name, email, and everything anyone wrote), and a column showing
which teammates have worked each thread. One click into a thread; reply
(Cmd/Ctrl+Enter sends), resolve, reopen. Both pages keep themselves fresh
while you watch — and never reload over a half-written reply or search.
Gated by `config.authorize_agent` (development-only until you set it).

## Widget API

- `window.Livechat.open()` / `window.Livechat.close()` —
  `open("Hi, I need help with…")` prefills the message box (never over a
  visitor's draft)
- Any element with `data-livechat-open` opens the panel on click; add
  `data-livechat-message="…"` to prefill — great for contextual buttons
  ("Request verification", "Ask about billing")
- While replies are unread, every `data-livechat-open` element carries a
  small count badge — so hiding the launcher doesn't hide the answer
- `<%= livechat_button %>` renders a plain, unstyled opener button
- `config.show_launcher = false` hides the bubble entirely — bring your own
  entry point

## What it doesn't do

No AI bots, no canned responses, no omnichannel (WhatsApp, Messenger…), no
visitor tracking, no "powered by" badge. If you need a support platform,
[Chatwoot](https://github.com/chatwoot/chatwoot) is excellent. If you need
your users to be able to reach you from inside your Rails app — this is a
gem's worth of exactly that.

## Testing

```bash
bundle exec rake test
bundle exec rubocop
```

## License

MIT.
