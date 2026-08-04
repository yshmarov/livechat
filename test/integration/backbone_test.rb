# frozen_string_literal: true

require 'test_helper'
require 'rails/generators'
require 'generators/livechat/install/install_generator'

# The invariants shared across this family of engines. Each one exists because
# breaking it produced a real failure in a host app, and each was invisible to
# the rest of the suite.
class BackboneTest < ActionDispatch::IntegrationTest
  # 1. A host that replaces the layout must still get the inbox's assets. They
  #    used to be declared in the gem's own layout, so `agent_layout` (and now
  #    base_controller_class) silently dropped the stylesheet and script:
  #    unstyled inbox, dead thread polling.
  test 'every inbox page carries its own assets, under any layout' do
    as_agent!
    conversation = start_conversation

    [nil, 'host_admin'].each do |layout|
      Livechat.config.agent_layout = layout if layout
      ['/livechat', "/livechat/#{conversation.id}"].each do |path|
        get path

        assert_response :ok, "#{path} (layout #{layout.inspect}) did not render"
        assert_includes response.body, 'dashboard.css?v=', "#{path} is missing the stylesheet"
        assert_includes response.body, 'dashboard.js?v=', "#{path} is missing the script"
        assert_includes response.body, 'class="lvc-dashboard"', "#{path} is missing the scoping wrapper"
      end
    end
  end

  # 2. Everything a host already styles. A bare `body`/`a`/`*` rule, or an
  #    unprefixed `.card`/`.container`, restyles the host's own chrome the moment
  #    its admin loads this file.
  test 'the stylesheet claims no selector outside its own namespace' do
    get '/livechat/dashboard.css'

    assert_response :ok
    top_level_selectors(response.body).each do |part|
      assert part.start_with?('.lvc-', ':root'),
             "top-level selector #{part.inspect} is not namespaced to the inbox"
    end
  end

  # 3. Custom properties collide BOTH ways: a host defining --bg would recolour
  #    the inbox, and the inbox would recolour the host.
  test 'the stylesheet prefixes every custom property' do
    get '/livechat/dashboard.css'

    properties = response.body.scan(/(--[a-z0-9-]+)\s*:/).flatten.uniq
    assert_predicate properties, :any?, 'expected the stylesheet to declare custom properties'
    properties.each do |property|
      assert property.start_with?('--lvc-'), "custom property #{property} could collide with a host's"
    end
  end

  # 4. base_controller_class reparents the INBOX only. If a widget endpoint
  #    shared a controller with the inbox, pointing this at a host's admin
  #    controller would demand a staff session from every visitor.
  test 'only the inbox hangs off the configured base controller' do
    assert_equal Livechat.base_controller, Livechat::DashboardController.superclass
    assert_equal ActionController::Base, Livechat::ApplicationController.superclass

    [Livechat::WidgetsController, Livechat::VisitorController,
     Livechat::AttachmentsController].each do |controller|
      assert_equal Livechat::ApplicationController, controller.superclass,
                   "#{controller} must not inherit the host's base controller"
    end

    [Livechat::ConversationsController, Livechat::MessagesController].each do |controller|
      assert_equal Livechat::DashboardController, controller.superclass
    end
  end

  test 'base_controller_class resolves a host class lazily, by name' do
    assert_equal 'ActionController::Base', Livechat.config.base_controller_class
    Livechat.config.base_controller_class = 'HostAdminBaseController'

    assert_equal HostAdminBaseController, Livechat.base_controller
  end

  # 5. A uuid-keyed host has a uuid active_storage_attachments.record_id, so a
  #    bigint table here can never hold a message attachment: `attach` raises
  #    NotNullViolation. The routes must accept a non-integer id to match.
  test 'record routes accept a non-integer primary key' do
    uuid = '0f8fad5b-d9cb-469f-a165-70867728950e'
    engine = Livechat::Engine.routes

    assert_equal({ controller: 'livechat/conversations', action: 'show', id: uuid },
                 engine.recognize_path("/#{uuid}", method: :get))
    assert_equal({ controller: 'livechat/attachments', action: 'show', id: uuid },
                 engine.recognize_path("/attachments/#{uuid}", method: :get))
  end

  test 'the fixed-name routes still win over the catch-all id route' do
    engine = Livechat::Engine.routes

    assert_equal 'livechat/widgets', engine.recognize_path('/dashboard.css', method: :get)[:controller]
    assert_equal 'livechat/widgets', engine.recognize_path('/widget.js', method: :get)[:controller]
    assert_equal 'livechat/visitor', engine.recognize_path('/widget/conversation', method: :get)[:controller]
    assert_equal 'livechat/conversations', engine.recognize_path('/', method: :get)[:controller]
  end

  # A comment containing a comma used to be split as if it were a selector list,
  # which invalidates the whole list and silently drops the rule that follows.
  # Three of these gems shipped that. Nothing in a rendered stylesheet should
  # ever have comment syntax in selector position.
  test 'no selector contains comment syntax' do
    get '/livechat/dashboard.css'

    stripped = response.body.gsub(%r{/\*.*?\*/}m, '')
    stripped.scan(/([^{}]*)\{/).flatten.each do |selector|
      refute_includes selector, '/*', "selector #{selector.strip.inspect} has an unclosed comment in it"
      refute_includes selector, '*/', "selector #{selector.strip.inspect} has a stray comment terminator"
    end
  end

  # Braces must balance once comments are removed, or a nesting bug has eaten a
  # rule somewhere.
  test 'the stylesheet braces balance' do
    get '/livechat/dashboard.css'

    stripped = response.body.gsub(%r{/\*.*?\*/}m, '')
    assert_equal stripped.count('{'), stripped.count('}'), 'unbalanced braces in dashboard.css'
  end

  private

  # Selectors at nesting depth 0 — the ones that can reach a host's markup.
  def top_level_selectors(css)
    css = css.gsub(%r{/\*.*?\*/}m, '')
    selectors = []
    buffer = +''
    depth = 0

    css.each_char do |char|
      case char
      when '{'
        head = buffer.strip
        selectors.concat(head.split(',').map(&:strip).reject(&:empty?)) if depth.zero? && !head.start_with?('@')
        depth += 1 unless head.start_with?('@')
        buffer = +''
      when '}'
        depth -= 1 if depth.positive?
        buffer = +''
      when ';'
        buffer = +''
      else
        buffer << char
      end
    end

    selectors
  end
end

# 6. A template is expanded at generate time, so the id option has to be the
#    resolved value — including on the engine's own foreign key, or a bigint
#    reference column ends up pointing at a uuid table.
class BackboneGeneratorTest < Rails::Generators::TestCase
  tests Livechat::Generators::InstallGenerator
  destination File.expand_path('../tmp/backbone', __dir__)
  setup :prepare_destination
  setup :write_routes

  test 'the tables and the internal foreign key follow the host primary_key_type' do
    with_primary_key_type(:uuid) do
      run_generator

      assert_migration 'db/migrate/create_livechat_tables.rb' do |migration|
        assert_match 'create_table :livechat_conversations, id: :uuid', migration
        assert_match 'create_table :livechat_messages, id: :uuid', migration
        assert_match 't.references :conversation, null: false, index: false, type: :uuid', migration
        refute_match 'primary_key_type', migration
        refute_match 'foreign_key_type', migration
      end
    end
  end

  test 'the tables take no id option when the host sets nothing' do
    with_primary_key_type(nil) do
      run_generator

      assert_migration 'db/migrate/create_livechat_tables.rb' do |migration|
        assert_match 'create_table :livechat_conversations do |t|', migration
        assert_match 't.references :conversation, null: false, index: false', migration
        refute_match 'type: :', migration
      end
    end
  end

  # `t.references` indexes by default, and (conversation_id) is a leftmost prefix
  # of (conversation_id, id) — so the automatic one was dead weight. A B-tree
  # serves any leftmost prefix.
  test 'no index duplicates a leftmost prefix of another' do
    run_generator

    assert_migration 'db/migrate/create_livechat_tables.rb' do |migration|
      indexes = migration.scan(/add_index :(\w+), (?:%i\[([\w\s]+)\]|:(\w+))/).map do |table, composite, single|
        [table, composite ? composite.split : [single]]
      end
      # t.references adds one too, unless index: false says otherwise.
      migration.scan(/t\.references :(\w+)([^\n]*)/).each do |name, opts|
        indexes << ['livechat_messages', ["#{name}_id"]] unless opts.include?('index: false')
      end

      indexes.each do |table, columns|
        others = indexes.reject { |t, c| t != table || c == columns }
        redundant = others.find { |_, other| other.first(columns.length) == columns }
        assert_nil redundant, "#{table} index on #{columns.inspect} is a prefix of #{redundant&.last.inspect}"
      end
    end
  end

  private

  # `route` needs somewhere to inject; without it the generator only warns.
  def write_routes
    FileUtils.mkdir_p(File.join(destination_root, 'config'))
    File.write(File.join(destination_root, 'config/routes.rb'), "Rails.application.routes.draw do\nend\n")
  end

  def with_primary_key_type(type)
    config = Rails.configuration.generators
    previous = config.options[config.orm][:primary_key_type]
    config.options[config.orm][:primary_key_type] = type
    yield
  ensure
    config.options[config.orm][:primary_key_type] = previous
  end
end
