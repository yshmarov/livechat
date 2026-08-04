# frozen_string_literal: true

Livechat::Engine.routes.draw do
  get 'widget.js', to: 'widgets#show', as: :widget
  get 'dashboard.js', to: 'widgets#dashboard', as: :dashboard_script
  get 'dashboard.css', to: 'widgets#dashboard_stylesheet', as: :dashboard_stylesheet

  # The widget's API. Everything is scoped to the requesting visitor —
  # signed-in id or guest cookie — never to an enumerable conversation id.
  scope :widget, as: :widget do
    get 'conversation', to: 'visitor#show'
    post 'messages', to: 'visitor#create'
    post 'typing', to: 'visitor#typing'
    post 'email', to: 'visitor#email'
    post 'read', to: 'visitor#read'
  end

  # Message attachments, gated by the engine (never a public blob URL). One
  # route for both sides — the controller decides whether you're the visitor
  # who owns the thread or an agent. Declared above the conversations catch-all,
  # which is what keeps it from being shadowed — no id constraint needed, and a
  # digits-only one would have made the tables bigint-only (see below).
  get 'attachments/:id', to: 'attachments#show', as: :attachment

  # The inbox. Flat, human URLs: the mount path IS the conversation list.
  # No `id: /\d+/` constraint: it made these routes bigint-only, which forced the
  # tables to be bigint too, and a uuid-keyed host could then never attach a file
  # (its active_storage_attachments.record_id is a uuid column). Every fixed-name
  # route above is declared first, so ordering already disambiguates.
  resources :conversations, path: '', only: %i[index show] do
    collection do
      get :poll, action: :index_poll
    end
    member do
      get :poll
      post :typing
      post :resolve
      post :reopen
    end
    resources :messages, only: :create
  end

  root to: 'conversations#index'
end
