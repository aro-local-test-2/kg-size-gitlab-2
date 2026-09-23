# frozen_string_literal: true

FactoryBot.define do
  factory :cd_rollout_incoming_event, class: 'Cd::RolloutIncomingEvent' do
    rollout { association(:cd_rollout) }
    sequence(:idempotency_key) { |n| "idempotency-key-#{n}" }
  end
end
