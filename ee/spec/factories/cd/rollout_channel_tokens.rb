# frozen_string_literal: true

FactoryBot.define do
  factory :cd_rollout_channel_token, class: 'Cd::RolloutChannelToken' do
    rollout { association(:cd_rollout) }
    sequence(:channel_name) { |n| "channel-#{n}" }
    token { SecureRandom.hex(16) }
  end
end
