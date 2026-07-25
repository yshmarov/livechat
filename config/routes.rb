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

  # The inbox. Flat, human URLs: the mount path IS the conversation list.
  resources :conversations, path: '', only: %i[index show], constraints: { id: /\d+/ } do
    member do
      get :poll
      post :resolve
      post :reopen
    end
    resources :messages, only: :create
  end

  root to: 'conversations#index'
end
