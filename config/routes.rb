# frozen_string_literal: true

Livechat::Engine.routes.draw do
  get 'widget.js', to: 'widgets#show', as: :widget
  get 'dashboard.js', to: 'widgets#dashboard', as: :dashboard_script

  # The widget's API. Everything is scoped to the requesting visitor —
  # signed-in id or guest cookie — never to an enumerable conversation id.
  scope :widget, as: :widget do
    get 'conversation', to: 'visitor#show'
    post 'messages', to: 'visitor#create'
    post 'email', to: 'visitor#email'
    post 'read', to: 'visitor#read'
  end

  # Message attachments, gated by the engine (never a public blob URL). One
  # route for both sides — the controller decides whether you're the visitor
  # who owns the thread or an agent. Above the conversations catch-all, and
  # id-constrained so it never shadows a numeric conversation path.
  get 'attachments/:id', to: 'attachments#show', as: :attachment, constraints: { id: /\d+/ }

  # The inbox. Flat, human URLs: the mount path IS the conversation list.
  resources :conversations, path: '', only: %i[index show], constraints: { id: /\d+/ } do
    collection do
      get :poll, action: :index_poll
    end
    member do
      get :poll
      post :resolve
      post :reopen
    end
    resources :messages, only: :create
  end

  root to: 'conversations#index'
end
