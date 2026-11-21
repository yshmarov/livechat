# frozen_string_literal: true

Rails.application.routes.draw do
  mount_livechat at: "/livechat"
  get "sample", to: "sample#show"
  get "support", to: "sample#support"
end
