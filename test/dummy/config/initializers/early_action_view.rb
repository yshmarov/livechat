# frozen_string_literal: true

# A host may configure Action View from an application initializer. That fires
# ActiveSupport's :action_view load hooks before Rails has installed the app
# autoloaders. Boot must still be able to resolve Livechat::WidgetHelper.
ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag }
