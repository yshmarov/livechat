# Security policy

## Supported versions

Security fixes are released for the latest 1.x version. If a report also
affects the newest 0.x release, a backport may be published when the fix is
small and the affected application cannot upgrade immediately.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/yshmarov/livechat/security/advisories/new)
and include the affected version, a minimal reproduction, impact, and any known
workaround. Do not include credentials, session cookies, visitor tokens,
private application URLs, customer messages, uploaded files, or production
database contents.

Public disclosure should wait until a fixed version is available and affected
users have had a reasonable opportunity to upgrade.

## Data and authorization boundary

The widget and visitor endpoints are controlled by `config.enabled`; the agent
inbox is separately protected by `authorize_agent` and fails closed outside
development until the host grants access. A visitor can read only the
conversation resolved from their signed-in id or opaque guest cookie. Every
authorized agent can read and answer every conversation in the mounted inbox.
Livechat 1.x does not provide tenant-isolated agent inboxes.

Conversations can store a visitor token, host user id and label, email, status,
query-free HTTP(S) page URL, locale, message preview, activity timestamps, and
record timestamps. Messages can store bodies, author type, agent id and label,
system events, read state, timestamps, and optional files. Page credentials,
query strings, fragments, executable URL schemes, and invalid URLs are not
stored. Message bodies are plain text and length-capped; rendering escapes
them rather than interpreting Markdown or HTML.

Attachments stream through the engine only after the request is authorized as
an agent or the owning visitor. Responses are private and `no-store`, support
byte ranges, and never redirect to a reusable signed blob URL. Hosts own the
storage service, bucket policy, backups, retention, malware controls, access
logs, and incident response. `allowed_attachment_types` is an application
allowlist, not content inspection or malware scanning.

Livechat has no vendor service and does not transmit conversation data to this
project. Host-configured notification email can include message content,
visitor context, and attachment filenames. `on_visitor_message` and
`on_agent_message` receive the saved message and can send it anywhere the host
chooses. Those email and hook destinations are part of the host's privacy and
retention boundary.

## Deletion and retention

Nothing is deleted automatically. Use the Active Record destroy lifecycle so
messages and Active Storage attachments follow their configured dependencies:

```ruby
Livechat::Conversation.find(id).destroy!
Livechat::Conversation.where(visitor_id: user.id.to_s).find_each(&:destroy!)
Livechat::Conversation.purge_resolved(older_than: 90.days.ago)
```

`purge_resolved` removes only resolved conversations whose last activity is
older than the supplied cutoff and returns the number destroyed. Open threads
are never removed by it. Do not use `delete_all` when dependent messages and
attachments must be removed.

Active Storage may enqueue blob purging through the host's Active Job adapter.
Confirm those jobs and deletion from object storage, replicas, backups, caches,
notification mailboxes, hook destinations, logs, analytics, and exports;
deleting live database rows does not rewrite those systems.
