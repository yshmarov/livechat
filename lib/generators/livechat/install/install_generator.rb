# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module Livechat
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Installs livechat: config initializer, migration, and engine mount.'

      def create_initializer
        copy_file 'initializer.rb', 'config/initializers/livechat.rb'
      end

      def create_migration_file
        migration_template 'create_livechat_tables.rb.tt',
                           'db/migrate/create_livechat_tables.rb'
      end

      def mount_engine
        route %(mount_livechat at: "/livechat")
      end

      def post_install
        say "\nlivechat installed. Run `rails db:migrate`, then add", :green
        say '`<%= livechat_tag %>` before </body> in your layout.'
        say 'Answer visitors at /livechat (development only until you set config.authorize_agent).'
        say "Set config.mailer_from + config.agent_emails to hear about new messages by email.\n"
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
