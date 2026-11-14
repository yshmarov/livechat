# frozen_string_literal: true

module Livechat
  module Generators
    # Shared bits every migration-writing generator needs.
    module MigrationHelpers
      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end

      # Follow the host's own key type instead of forcing bigint. An app that
      # keys its models with uuids has a uuid
      # `active_storage_attachments.record_id`, so a bigint table here could
      # never take a message attachment: the foreign key has nowhere to point
      # and `attach` raises NotNullViolation.
      #
      # Same lookup Rails' own Active Storage, Action Text and Action Mailbox
      # migrations do, so a host that set it once gets consistent tables from
      # all of them.
      #
      # Rendered as options rather than bare values, because a template is
      # expanded at generate time: emitting the method name would put
      # `id: primary_key_type` in the migration, where nothing defines it.
      def primary_key_type_option
        primary_key_type ? ", id: :#{primary_key_type}" : ''
      end

      # The engine's own foreign key (messages -> conversations) has to match
      # whatever the referenced table's primary key became, or the reference
      # column is a bigint pointing at a uuid.
      def foreign_key_type_option
        primary_key_type ? ", type: :#{primary_key_type}" : ''
      end

      def primary_key_type
        config = Rails.configuration.generators
        config.options[config.orm][:primary_key_type]
      end

      # Adding a foreign key to a table that already holds rows validates every
      # row while it locks out writes. On PostgreSQL the key can go in
      # unvalidated and be validated in a second statement that does not block
      # writes, which is also the only shape strong_migrations accepts. That
      # second statement must run outside the migration's transaction.
      #
      # Decided at generate time, like the key type, so the migration holds
      # plain code rather than an adapter check.
      def postgresql?
        ActiveRecord::Base.connection_db_config.adapter.to_s.include?('postg')
      end
    end
  end
end
