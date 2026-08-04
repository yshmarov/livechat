# frozen_string_literal: true

require_relative 'lib/livechat/version'

Gem::Specification.new do |spec|
  spec.name = 'livechat'
  spec.version = Livechat::VERSION
  spec.authors = ['Yaroslav Shmarov']
  spec.email = ['yaroslav.shmarov@clickfunnels.com']

  spec.summary = 'Open-source live chat for Rails: a drop-in support widget ' \
                 'plus a team inbox, in your own database.'
  spec.description = <<~DESC
    A mountable Rails engine that adds support chat to your app — the thing
    you'd otherwise pay Crisp or Intercom for, or deploy Chatwoot to get. A
    floating widget lets visitors (signed-in or anonymous) message your team;
    your team answers from a built-in inbox where several teammates can work
    the same thread, every reply signed with its author. When nobody is
    around, visitors leave an email and the conversation continues there.
    Conversations never leave your database. Framework-agnostic: no CSS or JS
    framework required, works with Turbo Drive and strict CSPs.
  DESC
  spec.homepage = 'https://github.com/yshmarov/livechat'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'app/**/*',
    'config/**/*',
    'lib/**/*',
    'MIT-LICENSE',
    'Rakefile',
    'README.md',
    'CHANGELOG.md',
    # Ships so an agent working in a host app can read the install guide
    # straight out of the bundle: `cat "$(bundle show livechat)/AGENTS.md"`.
    'AGENTS.md'
  ]
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '>= 7.1'
end
