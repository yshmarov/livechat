# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb'].exclude('test/system/**/*', 'test/ractor/**/*')
end

namespace :test do
  desc 'Run browser (system) tests'
  Rake::TestTask.new(:system) do |task|
    task.libs << 'test'
    task.test_files = FileList['test/system/**/*_test.rb']
  end
end

task default: :test

namespace :test do
  desc 'Run isolated configuration and Rails edge Ractor request tests (Ruby 4.0+)'
  task :ractor do
    ruby '-Itest', 'test/ractor/configuration_test.rb'
    ruby '-Itest', 'test/ractor/requests_test.rb'
  end
end
