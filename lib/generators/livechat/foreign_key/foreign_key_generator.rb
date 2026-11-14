# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'
require_relative '../migration_helpers'

module Livechat
  module Generators
    # For apps that installed livechat before 1.4: adds the foreign key from
    # livechat_messages.conversation_id to livechat_conversations. A fresh
    # install already has it. Nothing in the engine changes behavior; the
    # database just stops accepting a message for a conversation that does
    # not exist.
    #
    #   bin/rails generate livechat:foreign_key && bin/rails db:migrate
    class ForeignKeyGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      include MigrationHelpers

      source_root File.expand_path('templates', __dir__)

      desc 'Adds the messages -> conversations foreign key to an existing livechat install.'

      def create_migration_file
        migration_template 'add_livechat_messages_conversation_foreign_key.rb.tt',
                           'db/migrate/add_livechat_messages_conversation_foreign_key.rb'
      end

      def post_install
        say "\nForeign key queued. Run `rails db:migrate`.", :green
        say 'It fails if a message points at a conversation that no longer exists. Find those with:'
        say '  Livechat::Message.where.not(conversation_id: Livechat::Conversation.select(:id))'
      end
    end
  end
end
