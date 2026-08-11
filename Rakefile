# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb'].exclude('test/system/**/*')
end

namespace :test do
  desc 'Run browser (system) tests'
  Rake::TestTask.new(:system) do |task|
    task.libs << 'test'
    task.test_files = FileList['test/system/**/*_test.rb']
  end
end

task default: :test
