# frozen_string_literal: true

module Livechat
  # Used only by Rails' opt-in before_ractorize hook. Normal Rails boots keep
  # mutable configuration and lazy assets, including on older Ruby versions.
  module RactorSupport
    # Small bridges for framework paths that Rails main does not prepare yet.
    # They are installed only when the host explicitly calls ractorize!.
    # Rails' built-in JSON renderer is still defined from an unisolated Proc.
    # Keep its JSON/JSONP and escaping behavior in a regular Ruby method.
    module JsonRendering
      def _render_with_renderer_json(json, options)
        json_options = options.except(:callback, :content_type, :status)
        json_options[:escape] ||= false if !self.class.escape_json_responses? && options[:callback].blank?
        json = json.to_json(json_options) unless json.is_a?(String)
        if options[:callback].present?
          self.content_type = :js if media_type.nil? || media_type == Mime[:json]
          "/**/#{options[:callback]}(#{json})"
        else
          self.content_type = :json if media_type.nil?
          json
        end
      end
    end

    module DependencyInterlock
      def interlock
        return super if Ractor.main?

        Ractor[:engine_dependency_interlock] ||= ActiveSupport::Dependencies::Interlock.new
      end
    end

    module LiveThreads
      private

      def new_controller_thread
        return super if Ractor.main?

        Thread.new do
          Thread.current.abort_on_exception = true
          yield
        end
      end
    end

    module UniquenessCoverage
      private

      def covered_by_unique_index?(klass, record, attribute, scope)
        return super unless frozen?

        copies = Ractor[:engine_uniqueness_validators] ||= {}
        copy = copies[[self, klass]] ||= dup
        copy.send(:covered_by_unique_index?, klass, record, attribute, scope)
      end
    end

    # GlobalID calls CGI.unescape without an encoding, whose default reads a
    # process-wide class variable. Preserve CGI's configured default on main.
    module UriUnescaping
      def unescape(string, *arguments)
        return super if Ractor.main?

        shared_arguments = Ractor.make_shareable([string, *arguments], copy: true)
        ActiveSupport::Ractors.on_main(self) { unescape(*shared_arguments) }
      end
    end

    module CacheFreshness
      def strict_freshness
        return super if Ractor.main?

        ActiveSupport::Ractors.on_main(self) { strict_freshness }
      end
    end

    # Attribute decorators (including Rails enums and serialized attributes)
    # are boot-time factories. Keep their original receivers and captures on
    # the main Ractor, rather than changing the semantics of Rails' closures.
    class Decorator
      def initialize(callback)
        @key = RactorSupport.register_decorator(callback)
        freeze
      end

      def call(*arguments)
        return RactorSupport.call_decorator(@key, arguments) if Ractor.main?

        shared_arguments = Ractor.make_shareable(arguments, copy: true)
        ActiveSupport::Ractors.on_main(self) { RactorSupport.call_decorator(@key, shared_arguments) }
      end
    end

    def self.register_decorator(callback)
      @decorators ||= []
      @decorators << callback
      @decorators.length - 1
    end

    def self.call_decorator(key, arguments)
      @decorators.fetch(key).call(*arguments)
    end

    def self.prepare_attributes(model)
      prepare_attributes(model.superclass) if model.superclass.respond_to?(:pending_attribute_modifications, true)
      model.send(:pending_attribute_modifications)&.each do |modification|
        next unless modification.respond_to?(:decorator) && modification.decorator.is_a?(Proc)

        modification.decorator = Decorator.new(modification.decorator)
      end
    end

    module AdapterQuoting
      def quote_column_name(name)
        return super if Ractor.main?

        shared_name = Ractor.make_shareable(name, copy: true)
        ActiveSupport::Ractors.on_main(self) { quote_column_name(shared_name) }
      end

      def quote_table_name(name)
        return super if Ractor.main?

        shared_name = Ractor.make_shareable(name, copy: true)
        ActiveSupport::Ractors.on_main(self) { quote_table_name(shared_name) }
      end
    end

    # Route arguments can contain records with native Set caches. Only their
    # to_param value is needed to generate a mount prefix; keep the caller's
    # original record objects in the options passed to the actual route.
    def self.routing_snapshot(value)
      return value if Ractor.shareable?(value)

      copy = case value
             when ActiveRecord::Base then value.to_param
             when Hash then value.to_h { |key, item| [routing_snapshot(key), routing_snapshot(item)] }
             when Array then value.map { |item| routing_snapshot(item) }
             when Set then Set.new(value.map { |item| routing_snapshot(item) })
             else return Ractor.make_shareable(value, copy: true)
             end
      Ractor.make_shareable(copy)
    end

    module MountedRoutes
      def find_script_name(options)
        return super unless defined?(Ractor.shareable_proc) && !Ractor.main?

        shared_options = RactorSupport.routing_snapshot(options)
        prefix, updated = ActiveSupport::Ractors.on_main(self) do
          local_options = shared_options.dup
          [find_script_name(local_options), local_options]
        end
        (shared_options.keys - updated.keys).each { |key| options.delete(key) }
        updated.each do |key, value|
          options[key] = value unless shared_options.key?(key) && shared_options[key] == value
        end
        prefix
      end
    end

    module Digesting
      def hexdigest(value)
        return super if Ractor.main?

        shared_value = Ractor.make_shareable(value, copy: true)
        ActiveSupport::Ractors.on_main(self) { hexdigest(shared_value) }
      end
    end

    module KeyGeneration
      def generate_key(salt, key_size = 64)
        return super if Ractor.main?

        shared_salt = Ractor.make_shareable(salt, copy: true)
        ActiveSupport::Ractors.on_main(self) { generate_key(shared_salt, key_size) }
      end
    end

    module UploadCleanup
      def open
        reopen(path, 'rb+')
        self
      end

      # Tempfile#close takes a positional unlink flag.
      def close(unlink_now = false) # rubocop:disable Style/OptionalBooleanParameter
        super() unless closed?
        unlink if unlink_now
      end

      def unlink
        File.unlink(path)
      rescue Errno::ENOENT
        nil
      end

      def close!
        close(true)
      end
    end

    def self.upload_tempfile(filename, _content_type)
      extension = File.extname(filename.gsub("\0", '%00'))[0, 129]
      Tempfile.create(['RackMultipart', extension]).extend(UploadCleanup)
    end

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        if (fallbacks = RactorSupport.fallbacks)
          Fiber[:i18n_fallbacks] ||= fallbacks
          env['rack.multipart.tempfile_factory'] ||= RactorSupport.method(:upload_tempfile) unless Ractor.main?
        end
        @app.call(env)
      end
    end

    def self.fallbacks
      @fallbacks
    end

    module StorageMetadata
      def analyzed = read_store_attribute(:metadata, :analyzed)
      def identified = read_store_attribute(:metadata, :identified)
      def composed = read_store_attribute(:metadata, :composed)

      def analyzed=(value)
        write_store_attribute(:metadata, :analyzed, value)
      end

      def identified=(value)
        write_store_attribute(:metadata, :identified, value)
      end

      def composed=(value)
        write_store_attribute(:metadata, :composed, value)
      end
    end

    class StorageServices
      def initialize(configurations)
        @configurations = Ractor.make_shareable(configurations, copy: true)
        freeze
      end

      def fetch(name, &)
        registry = if Ractor.main?
                     RactorSupport.storage_registry
                   else
                     Ractor[:engine_storage_services] ||= ActiveStorage::Service::Registry.new(@configurations)
                   end
        registry.fetch(name, &)
      end
    end

    def self.storage_registry
      @storage_registry
    end

    module StorageChecksums
      def checksum_implementation(**options)
        implementation = super
        if Ractor.main? || !implementation.respond_to?(:name) || !implementation.name&.start_with?('OpenSSL::Digest::')
          return implementation
        end

        DigestFactory.new(implementation.name.delete_prefix('OpenSSL::Digest::'))
      end
    end

    class DigestFactory
      def initialize(algorithm)
        @algorithm = algorithm.freeze
        freeze
      end

      def new
        OpenSSL::Digest.new(@algorithm)
      end

      def file(io)
        new.file(io)
      end

      def base64digest(value)
        new.base64digest(value)
      end
    end

    def self.prepare_redirects!
      base = ActionController::Base
      readers = Module.new
      %i[raise_on_open_redirects action_on_open_redirect action_on_path_relative_redirect].each do |key|
        source = base.method(key).source_location&.first
        next unless source&.end_with?('/action_controller/metal/redirecting.rb')

        value = Ractor.make_shareable(base.public_send(key), copy: true)
        readers.define_method(key, Ractor.shareable_proc { Ractor.main? ? super() : value })
      end
      return if readers.instance_methods(false).empty?

      base.prepend(readers)
      base.singleton_class.prepend(readers)
    end

    def self.prepare_previewers!
      ActiveStorage.previewers.each do |previewer|
        readers = Module.new
        previewer.methods.grep(/_exists\?\z/).each do |capability|
          method = previewer.method(capability)
          next unless method.arity.zero? && method.source_location&.first&.include?('/active_storage/previewer/')

          readers.define_method(capability, Ractor.shareable_proc do
            if Ractor.main?
              super()
            else
              ActiveSupport::Ractors.on_main(self) { public_send(capability) }
            end
          end)
        end
        previewer.singleton_class.prepend(readers) unless readers.instance_methods(false).empty?
      end
    end

    def self.prepare_storage!
      return unless defined?(ActiveStorage::Blob)

      prepare_previewers!
      ActiveStorage::Blob.prepend(StorageMetadata) unless ActiveStorage::Blob < StorageMetadata
      %i[EXTENSIONS TYPE_EXTS TYPE_ALIASES TYPE_PARENTS ROOT_XML MAGIC].each do |name|
        Ractor.make_shareable(Marcel.const_get(name)) if Marcel.const_defined?(name)
      end
      ActiveStorage::Service.prepend(StorageChecksums) unless ActiveStorage::Service < StorageChecksums
      unless Ractor.shareable?(ActiveStorage::Blob.services)
        @storage_registry = ActiveStorage::Blob.services
        configurations = @storage_registry.instance_variable_get(:@configurations)
        default_name = ActiveStorage::Blob.service.name
        default_reader = Module.new
        default_reader.define_method(:service, Ractor.shareable_proc do
          Ractor.main? ? super() : services.fetch(default_name)
        end)
        ActiveStorage::Blob.singleton_class.prepend(default_reader)
        ActiveStorage::Blob.services = StorageServices.new(configurations)
      end
      settings = ActiveStorage.class_variables.map { |name| name.to_s.delete_prefix('@@').to_sym }
      settings.select! { |key| ActiveStorage.respond_to?(key) }
      snapshot = settings.to_h { |key| [key, ActiveStorage.public_send(key)] }
      checksum = snapshot[:checksum_implementation]
      if checksum.is_a?(Class) && checksum.name&.start_with?('OpenSSL::Digest::')
        snapshot[:checksum_implementation] = DigestFactory.new(checksum.name.delete_prefix('OpenSSL::Digest::'))
      end
      Ractor.make_shareable(snapshot)
      readers = Module.new
      settings.each do |key|
        readers.define_method(key, Ractor.shareable_proc { Ractor.main? ? super() : snapshot.fetch(key) })
      end
      ActiveStorage.singleton_class.prepend(readers)
    end

    def self.prepare_framework!
      CGI.singleton_class.prepend(UriUnescaping) unless CGI.singleton_class < UriUnescaping
      Ractor.make_shareable(GlobalID.app) if defined?(GlobalID) && GlobalID.respond_to?(:app)
      I18n.available_locales.each { |locale| I18n.transliterate('ractor', locale: locale) }
      require 'i18n/ractorize'
      require 'tempfile'
      prepare_redirects!
      %i[BASE36_ALPHABET BASE58_ALPHABET].each do |name|
        Ractor.make_shareable(SecureRandom.const_get(name)) if SecureRandom.const_defined?(name)
      end
      uniqueness = ActiveRecord::Validations::UniquenessValidator
      uniqueness.prepend(UniquenessCoverage) unless uniqueness < UniquenessCoverage
      dependencies = ActiveSupport::Dependencies.singleton_class
      dependencies.prepend(DependencyInterlock) unless dependencies < DependencyInterlock
      prepare_storage!
      Ractor.make_shareable(ActiveRecord::Associations::AssociationScope::INSTANCE)
      Ractor.make_shareable(ActionDispatch::Http::Cache::Response::SPECIAL_KEYS)
      freshness = ActionDispatch::Http::Cache::Request.singleton_class
      freshness.prepend(CacheFreshness) unless freshness < CacheFreshness
      fallbacks = I18n.fallbacks
      I18n.available_locales.each { |locale| fallbacks[locale] }
      @fallbacks = Ractor.make_shareable(fallbacks)
      ActiveSupport::Digest.singleton_class.prepend(Digesting) unless ActiveSupport::Digest.singleton_class < Digesting
      ActiveSupport::KeyGenerator.prepend(KeyGeneration) unless ActiveSupport::KeyGenerator < KeyGeneration
      ActiveRecord::Base.connection_handler.connection_pool_list.each do |pool|
        adapter = pool.db_config.adapter_class.singleton_class
        adapter.prepend(AdapterQuoting) unless adapter < AdapterQuoting
      end
    rescue LoadError => e
      raise LoadError,
            "Ractor requests need the upstream I18n Ractor support (see gemfiles/rails_ractor.gemfile): #{e.message}"
    end

    def self.broadcast(name, payload)
      if @prepared && !Ractor.main?
        shared_name = Ractor.make_shareable(name, copy: true)
        shared_payload = Ractor.make_shareable(payload, copy: true)
        ActiveSupport::Ractors.on_main { ActionCable.server.broadcast(shared_name, shared_payload) }
      else
        ActionCable.server.broadcast(name, payload)
      end
    end

    def self.prepare!
      # A cache store can reference the whole middleware stack and freeze
      # other mounted engines before their own hooks run. Warm every engine's
      # request environment before making any of that graph shareable.
      Rails.application.railties.each do |railtie|
        railtie.env_config if railtie.is_a?(Rails::Engine)
      end
      Engine.instance.env_config
      prepare_framework!
      ActiveRecord::Base.descendants.each do |model|
        next if model.abstract_class? || !model.table_exists?

        model.reflect_on_all_associations.each { |reflection| reflection.send(:inverse_name) }
        prepare_attributes(model)
        Ractor.make_shareable(model.defined_enums)
        model.defined_enums.each do |attribute, mapping|
          method_name = attribute.pluralize
          source = model.method(method_name).source_location&.first
          next unless source&.end_with?('/active_record/enum.rb')

          model.define_singleton_method(method_name, Ractor.shareable_proc { mapping })
        end
        model.define_attribute_methods
        if model.respond_to?(:attachment_reflections)
          model.attachment_reflections.each_value(&:named_variants)
          Ractor.make_shareable(model.attachment_reflections)
        end
      end
      ActionController::Base.descendants.each do |controller|
        next unless controller.name&.start_with?('Livechat::')

        controller.prepend(LiveThreads) if defined?(ActionController::Live) && controller < ActionController::Live
        renderer_source = controller.instance_method(:_render_with_renderer_json).source_location&.first
        if renderer_source&.end_with?('/action_controller/metal/renderers.rb') && !(controller < JsonRendering)
          controller.prepend(JsonRendering)
        end
        Ractor.make_shareable(controller.controller_name)
        controller.etaggers = controller.etaggers.map { |callback| Ractor.shareable_proc(&callback) }.freeze
      end
      Livechat.instance_variable_set(:@config, configuration(Livechat.config))
      %i[javascript dashboard_javascript dashboard_stylesheet fingerprint
         dashboard_fingerprint dashboard_stylesheet_fingerprint].each do |method|
        next unless Widget.respond_to?(method)

        Widget.public_send(method)
      end
      ActionController::Base.descendants.each do |controller|
        next unless controller.respond_to?(:livechat_rate_limit_options)

        options = controller.livechat_rate_limit_options
        controller.livechat_rate_limit_options = share_options(options)
      end
      if Livechat.config.action_cable && defined?(ActionCable)
        verifier = Livechat.stream_verifier
        verifier.verify(verifier.generate('livechat:ractor:warmup'))
        Livechat.instance_variable_set(:@stream_verifier, Ractor.make_shareable(verifier))
      end
      @prepared = true
      Widget.instance_variables.each do |variable|
        Widget.instance_variable_set(variable, Ractor.make_shareable(Widget.instance_variable_get(variable)))
      end
    end

    # Rails edge's rate_limit currently closes over reassigned keyword
    # arguments. A named filter avoids that unshareable closure; the actual
    # counter, cache key and rejection still use Rails' rate_limiting method.
    def self.rate_limit(controller, to:, within:, only:, with:, **options)
      unless Rails::Application.method_defined?(:ractorize!)
        return controller.rate_limit(to: to, within: within, only: only, with: with, **options)
      end

      controller.class_attribute :livechat_rate_limit_options, instance_accessor: false
      controller.livechat_rate_limit_options = {
        to: to, within: within, by: -> { request.remote_ip }, with: with,
        store: controller.cache_store, name: nil, scope: controller.controller_path
      }.merge(options.slice(:by, :store, :name, :scope))
      controller.livechat_rate_limit_options[:scope] ||= controller.controller_path
      filters = options.except(:by, :store, :name, :scope)
      controller.before_action :livechat_rate_limit, only: only, **filters
      controller.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        private
        def livechat_rate_limit
          rate_limiting(**self.class.livechat_rate_limit_options)
        end
      RUBY
    end

    def self.share_options(options)
      options.to_h do |key, value|
        value = configuration_value(value) if value.is_a?(Proc)
        [key, Ractor.make_shareable(value)]
      end.freeze
    end

    def self.configuration_value(value)
      case value
      when Proc
        return value if Ractor.shareable?(value)

        # Like Rails callbacks, isolated callbacks use arguments and constants,
        # not their initializer's implicit self. Keep lambda/proc arity intact.
        value.lambda? ? Ractor.shareable_lambda(&value) : Ractor.shareable_proc(&value)
      when Hash
        value.to_h { |key, item| [configuration_value(key), configuration_value(item)] }.freeze
      when Array
        value.map { |item| configuration_value(item) }.freeze
      else
        Ractor.make_shareable(value, copy: true)
      end
    end

    def self.configuration(original)
      prepared = original.dup
      original.instance_variables.each do |variable|
        value = original.instance_variable_get(variable)
        begin
          shared = configuration_value(value)
          prepared.instance_variable_set(variable, shared)
        rescue Ractor::Error, TypeError => e
          setting = variable.to_s.delete_prefix('@')
          raise ArgumentError, "Livechat.config.#{setting} cannot be shared with Ractors: #{e.message}"
        end
      end
      Ractor.make_shareable(prepared)
    end
  end
end
