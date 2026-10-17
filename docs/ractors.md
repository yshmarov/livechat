# Rails edge and experimental Ractor hosting

The regular CI matrix covers Rails 7.1, 7.2, 8.0 and 8.1. A required Rails
edge job runs the same suite against `rails/rails` main. A separate job boots
an eager-loaded host, calls `Rails.application.ractorize!`, and sends real
Rack requests through the mounted engine in non-main Ractors, including
simultaneous requests. The Ractor checks run in separate processes because
Ractorization freezes Rails; they never freeze the ordinary test application.

## Host prerequisites

Ractor hosting currently requires Ruby 4.0+, Rails main, Rack main's
`rack/ractorize`, and the unreleased [I18n Ractor support](https://github.com/ruby-i18n/i18n/pull/741).
`gemfiles/rails_ractor.gemfile` records the exact I18n revision tested. These
are development/test dependencies, not new runtime dependencies for released
Rails. The gem's supported dependency range remains Rails >= 7.1 and < 9.

For a host experimenting with Ractor hosting, the tested upstream overrides are:

```ruby
gem "rails", github: "rails/rails", branch: "main"
gem "rack", github: "rack/rack", branch: "main"
gem "i18n", github: "Shopify/i18n", ref: "58aa1dcd3e04c34831e1c2ec06c83391559c7c91"
```

Follow Rails' own Ractor hosting requirements: disable reloading, eager-load
application code, use a shareable logger/cache and a Ractor-compatible job
adapter. Before application classes load, enable Rails' callback isolation:

```ruby
require "active_support/ractors"
ActiveSupport::Ractors.unshareable_proc_action = :raise
```

Our isolated fixture uses `ActiveSupport::Ractors::Logger`, a null
cache, and (where jobs are loaded) `:inline`. Its separate shared counter proves
that public submission limits remain effective across worker Ractors. The
ordinary dummy application's `:test` job adapter is unchanged.

The engine prepares itself automatically on `before_ractorize`; ordinary Rails
boots do not freeze its configuration or load the experimental I18n extension.
An unavailable I18n Ractor extension produces a startup error explaining the
prerequisite. Rails edge and Ractor hosting remain experimental: this is not a
promise that every third-party host middleware, database driver, storage
service, mail adapter or Action Cable adapter is Ractor safe.

## Configuration and callbacks

Finish configuring Livechat before calling `ractorize!`. The engine publishes
a frozen copy of the configuration and warms/freezes widget JS, CSS and content
fingerprints. Changes after Ractorization require a process restart. Arrays and
hashes supplied by the host are copied before freezing.

Callbacks are isolated with Ruby's `Ractor.shareable_lambda` or
`Ractor.shareable_proc`, preserving lambda/proc arity. They continue to receive
the same request, user, record or event arguments and run on each request.
Isolated callbacks use arguments and constants; their implicit initializer
`self` becomes nil, following Rails' isolated callback convention.

```ruby
Livechat.configure do |config|
  config.enabled = ->(request) { request.get_header("HTTP_X_WIDGET") != "off" }
end
```

Immutable captured values must already be shareable:

```ruby
expected_host = "app.example.com".freeze
Livechat.configure do |config|
  config.enabled = ->(request) { request.host == expected_host }
end
```

Mutable captures (an array collecting notifications, an unfrozen captured
string, or reassigned outer locals) cannot be shared. The engine fails at
startup with `Livechat.config.<setting>` in the error rather than failing on
a visitor's request. Use request-local state and external persistence for
side effects. A pre-isolated callback made with an explicit shareable `self:`
keeps that receiver. Stateful callable objects must be copyable/shareable;
custom objects remain subject to Ruby's Ractor rules.

## Scope and cost

Some Rails main paths are still being converted to Ractors. The engine warms
model attributes and controller names, prepares ETag callbacks, and supplies
narrow bridges for mounted URL generation, cache freshness, digest/key
operations, GlobalID URI decoding and boot-time attribute decorators. Those bridges preserve the
original operation on the main Ractor; requests, authorization callbacks,
rendering and persistence orchestration execute in their worker Ractors.
Adapter name quoting delegates to its original implementation on the main Ractor,
which preserves escaping and avoids process-global mutable caches in workers.
Disk-backed uploads use Ractor-local storage clients and plain temporary files
with explicit cleanup, because Tempfile's generated delegation methods cannot
be called from another Ractor. MIME registrations must finish before
Ractorization, when Marcel's MIME tables become immutable. Eager model schema
preparation adds startup database work.
The bridges are internal compatibility code, add coordination overhead, and
must be reviewed as upstream Rails evolves. No throughput improvement is claimed.

## Run the checks

Use the Ruby configured in `mise.toml`, never macOS's system Ruby.

```sh
BUNDLE_GEMFILE=gemfiles/rails_edge.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_edge.gemfile bundle exec rake test
BUNDLE_GEMFILE=gemfiles/rails_ractor.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_ractor.gemfile bundle exec rake test:ractor
```

The request fixture creates and removes its own temporary database and host;
it does not reuse or freeze `test/dummy`. The shared schema lives in
`test/support/schema.rb` so the ordinary and Ractor suites exercise the same
record shape. Successful checks establish the tested SQLite host and explicit
request paths, not all combinations of host integrations.

The media job also runs with `RACTOR_MEDIA=1`, exercising private disk-backed
Active Storage downloads through the engine's authorization gate. Storage
services are initialized per Ractor, and streamed responses use a thread local
to that Ractor. Livechat additionally runs with `RACTOR_CABLE=1`, checking the
signed stream token and broadcasts delegated to the main Action Cable server.
Other storage services and production Cable adapters need host-specific QA.
