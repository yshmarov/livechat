# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'capybara'
  gem 'puma'
  gem 'rack-test'
  # Pinned: RuboCop ships new and changed cops in minor releases, and no
  # Gemfile.lock is committed here (a gem resolves against a range — that is
  # what the gemfiles/ matrix tests), so an unpinned linter means CI can turn
  # red on a day nobody touched this repo. 1.89 doing exactly that is why the
  # constraint exists. Bump it deliberately, then fix what it finds.
  gem 'rubocop', '~> 1.89.0', require: false
  gem 'selenium-webdriver'
  gem 'sqlite3'
end
