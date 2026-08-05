# AGENTS.md

Instructions for coding agents. Two audiences:

- **[Installing livechat into a Rails app](#installing-into-a-rails-app)** — you are working in a host app and were asked to add support chat, live chat, or an in-app inbox.
- **[Working on the gem itself](#working-on-the-gem-itself)** — you are working in this repository.

Requirements: Ruby >= 3.2, Rails >= 7.1. Active Storage only for file attachments. **No Redis and no Action Cable** — the transport is polling unless you opt in.

If you are in a host app and this file is not in front of you, it ships inside the gem: `cat "$(bundle show livechat)/AGENTS.md"`.

---

## Installing into a Rails app

### 1. Install

```bash
bundle add livechat
bin/rails generate livechat:install
bin/rails db:migrate
```

The generator writes `config/initializers/livechat.rb`, one migration (`livechat_conversations`, `livechat_messages`), and `mount_livechat at: "/livechat"` into `config/routes.rb`. Read the initializer it wrote — every option is documented there in comments, and it is the source of truth over any summary of it, including this file.

Every `config.…` line below belongs inside the `Livechat.configure do |config|` block in that initializer. Uncomment and edit in place rather than appending a second `configure` block.

### 2. Wire the three things the generator cannot

**a. The widget tag.** Nothing appears until this is on the page:

```erb
<%# app/views/layouts/application.html.erb, before </body> %>
<%= livechat_tag %>
```

The helper is injected into ActionView by the engine — no include, no import, no asset pipeline entry. It renders the launcher bubble bottom-right.

**b. `authorize_agent` — do this before deploying.** The inbox at `/livechat` defaults to **development only**. It fails closed, so shipping without this is not an open inbox — it is a 403 reading "Forbidden. Set Livechat.config.authorize_agent to grant access."

```ruby
config.authorize_agent = ->(request) { request.env["warden"]&.user&.admin? }
```

**c. Visitor identity**, if the app has users. Without it every visitor is a cookie-tracked guest, and nobody in the inbox has a name.

```ruby
config.current_user  = ->(request) { request.env["warden"]&.user }
config.visitor_label = ->(user) { user.name }        # what the inbox shows
config.agent_label   = ->(user) { user.name }        # signed onto each reply
```

> **`current_user`, `enabled` and `authorize_agent` receive the raw `request`, not a controller.** Writing `->(request) { current_user }` is the most common mistake here — that method does not exist in this scope. Resolve the user *from the request*: Warden env, a signed cookie, `Current.user` if middleware already set it. Note the different shapes: `visitor_label` and `agent_label` receive the **user**, while `agent_display_name` receives the already-stored **label string**.

Rails 8 built-in auth:

```ruby
config.current_user = lambda do |request|
  token = request.cookies["session_token"]
  Session.find_signed(token)&.user if token
end
```

### 3. Verify

```bash
bin/rails routes | grep livechat     # engine mounted
bin/rails livechat:seed_demo         # optional sample conversations, idempotent
```

Then in the running app: load any page, confirm the bubble appears bottom-right, send a message, and answer it at `/livechat`.

### Opening the widget

| Way | How |
| --- | --- |
| The launcher bubble | On by default. `config.show_launcher = false` to remove it |
| Your own element | `<%= livechat_button %>`, or any element with `data-livechat-open` |
| JavaScript | `window.Livechat.open()` |

A visitor has **one conversation**, not a queue of tickets — writing again reopens the same thread. Signed-in visitors keep it across devices (keyed by user id); guests are tracked by cookie.

### Email notifications need two settings, not one

```ruby
config.mailer_from = "support@example.com"   # required, or nothing sends
config.agent_emails = ["team@example.com"]   # array, or a callable returning one
```

Setting `agent_emails` alone sends nothing: `mailer_from` is what switches email on (`Livechat.config.emails_enabled?` is `mailer_from.present?`). Notification is one email per unread stretch, not one per message.

### Realtime is opt-in

Polling is the default transport, on purpose — a host with no Action Cable works untouched. Turning on push requires the host to actually mount a cable:

```ruby
config.action_cable = true
config.action_cable_url = "/cable"   # keep in sync with the mount in routes.rb
```

Leave it off unless the app already has Action Cable working. Polling is not a degraded mode here.

### Attachments

`config.attach_files` is on by default but **silently inert without Active Storage** in the host app (`rails active_storage:install`) — the widget keeps working, just without a paperclip. Caps: `max_attachments` (5), `max_attachment_size` (10 MB), `allowed_attachment_types` (nil = any). Files are served through the engine at `/livechat/attachments/:id`, gated per request — never a public blob URL. Do not build your own blob links.

### Do not

- **Do not copy the widget JavaScript into `app/javascript`, or add a `<script>` tag for it.** `livechat_tag` renders what is needed, and the engine serves the code with a content fingerprint. There is no build step and nothing for esbuild/importmap/Tailwind to know about.
- **Do not rebuild the inbox, and do not edit views inside the gem.** To put it inside an admin you already have, set `config.base_controller_class = "Admin::BaseController"` — it inherits that controller's layout, helpers, authentication and request context. For the shell alone, `config.agent_layout = "admin/application"`. Both work with nothing else wired up: the inbox's own assets are declared by its views, not the layout.
- **Do not add an Action Cable mount to "make chat realtime"** unless you also set `config.action_cable = true`. Polling is the default and is not broken.
- **Do not set config outside the initializer.** `rate_limit` in particular is read when the controller class loads; assigning config per-request mutates it process-wide.
- **Do not expose attachments by blob URL** — the engine's gated route exists so a leaked signed URL cannot hand over a customer's file.

### Configuration worth knowing

Everything is optional; a fresh install works with zero config. Full list with comments is in the generated initializer.

| Option | Default | Note |
| --- | --- | --- |
| `authorize_agent` | development only | **Who can read the inbox. Set before deploying.** |
| `base_controller_class` | `ActionController::Base` | Controller the inbox inherits. Name your admin's and it adopts that layout, helpers, authentication and request context. Public endpoints never inherit it. |
| `enabled` | everyone | Per-request gate for the widget and its endpoints |
| `current_user` | `nil` | Receives the request; nil means guest-by-cookie |
| `visitor_label`, `agent_label` | name/email/to_s | Receive the user |
| `agent_display_name` | the label unchanged | Receives the label; return "Support team" to keep agents anonymous |
| `app_name`, `greeting`, `reply_time_text`, `launcher_label` | localized defaults | Widget copy |
| `avatar_url`, `accent_color` | `nil` | Header avatar (URL or callable) and brand hex |
| `show_launcher` | `true` | `false` = open only from your own elements |
| `mailer_from` | `nil` | **Required for any email at all** |
| `agent_emails` | `nil` | Array or callable |
| `attach_files` | `true` | Needs Active Storage; inert without it |
| `storage_service` | app default | A `storage.yml` key for a dedicated bucket |
| `max_attachments`, `max_attachment_size` | `5`, `10.megabytes` | Enforced server-side |
| `allowed_attachment_types` | `nil` | Content-type allowlist |
| `action_cable`, `action_cable_url` | `false`, `"/cable"` | Opt-in push |
| `rate_limit` | `{ to: 30, within: 60 }` | Rails 7.2+; ignored on 7.1. `nil` disables |
| `mount_path` | `"/livechat"` | Keep in sync with `mount_livechat at:` |
| `on_visitor_message`, `on_agent_message` | no-ops | Run inline after save — Slack, Noticed, push |

Turbo Drive and strict nonce-based CSP work out of the box. 26 locales ship with the gem, RTL included.

### Common failure modes

| Symptom | Cause |
| --- | --- |
| `NameError` for one of your own helpers in the inbox | `isolate_namespace` scopes `helper` to the engine. Use `config.base_controller_class` so the inbox inherits your helpers, rather than `agent_layout` alone. |
| `NotNullViolation` attaching a file on a uuid-keyed app | The tables were generated bigint. Set `primary_key_type` in `config.generators` before installing, or migrate them to uuid. |
| `/livechat` returns 403 "Set Livechat.config.authorize_agent to grant access" | Exactly what it says: still at the development-only default |
| No bubble on the page | `livechat_tag` missing from the rendered layout, `config.enabled` false, or `show_launcher = false` with no opener of your own |
| No notification emails | `mailer_from` not set — `agent_emails` alone does nothing |
| Messages only appear on refresh | Expected: polling is the default. `config.action_cable = true` (with `/cable` mounted) for push |
| No attachment button | Active Storage not installed, or `attach_files = false` |
| `undefined local variable current_user` in the initializer | A gate lambda treated its argument as a controller. It is a `request` |

---

## One family

`testimonials`, `ideasbugs`, `product_tours`, `i18n_proofreading` are the sibling engines. Same install shape, same host hooks (`base_controller_class`, `agent_layout`), same scoped dashboard CSS, same `primary_key_type`-aware migrations — so what you learn here transfers.

## Working on the gem itself

```bash
bundle exec rake test            # minitest, dummy app under test/dummy
bundle exec rubocop              # must be clean
BUNDLE_GEMFILE=gemfiles/rails_7.1.gemfile bundle exec rake test   # 7.1, 7.2, 8.0, 8.1 in gemfiles/
```

Layout: `app/` controllers, models, inbox views, mailer · `lib/livechat/` config, widget JS/CSS, seeds, engine, channels · `lib/generators/livechat/install/` the one generator · `config/locales/` 26 locales · `test/` minitest, `test/dummy` the host app.

Conventions this codebase holds to — follow them rather than the first thing that works:

- **Polling is the baseline, Action Cable is opt-in.** Nothing may require a cable to be mounted. The channel lives under `lib/` and is required only when `ActionCable` is defined, so eager-loading an app without it cannot fail.
- **Active Storage is optional at runtime.** Attachment code checks for it rather than assuming it; an app without Active Storage gets a working widget, not an exception.
- **The widget is plain ES5-style JS served by the engine**, no build step, no framework, config read from a JSON block so a Turbo visit re-reads the current page's settings.
- **Visitor scoping is never by conversation id.** The widget's endpoints resolve the thread from the signed-in id or the guest cookie, so no id in a request can address someone else's conversation. Keep it that way.
- **The dummy app pins `config.active_job.queue_adapter = :test`.** Do not remove it or let it drift back to the `:async` default. Attaching a file enqueues Active Storage's analysis job, and `:async` runs it on a background thread that checks out its own connection — writes no test transaction covers, landing in the middle of whatever runs next. That is a suite that fails order-dependently in a test which never created a row, and it is miserable to trace back.
- **`lib/livechat/dashboard.css` is half shared.** Everything above the `GEM-SPECIFIC` banner is the design system all five gems in the family ship — the same tokens, the same `.page-head`/`.tabs`/`.filters`/`.card`/`.badge`/`button`/`.status-switch`, the same `.dashboard-shell` + `.record-row` + `.detail-panel` two-pane dashboard — identical in every repo apart from the `lvc` prefix. Diff it against a sibling before changing it, and carry the change to the other four. Anything only this gem has goes below the banner. New dashboard markup reuses the shared class names rather than inventing a domain-specific one.
- Every user-facing change bumps `lib/livechat/version.rb` and adds a `CHANGELOG.md` entry that says what it costs, not only what it adds.
- Commit messages are prose that explains the tradeoff — read `git log` before writing one.
