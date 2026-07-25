# frozen_string_literal: true

module Livechat
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
