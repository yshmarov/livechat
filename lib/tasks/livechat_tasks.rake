# frozen_string_literal: true

namespace :livechat do
  desc 'Create or refresh livechat demo conversations'
  task seed_demo: :environment do
    conversations = Livechat::Seeds.load!
    puts "Seeded #{conversations.size} livechat demo conversations."
  end
end
