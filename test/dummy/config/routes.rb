# frozen_string_literal: true

Rails.application.routes.draw do
  mount Livechat::Engine => "/livechat"
  get "sample", to: "sample#show"
end
