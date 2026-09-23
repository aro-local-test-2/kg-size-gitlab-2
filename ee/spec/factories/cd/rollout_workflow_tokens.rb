# frozen_string_literal: true

FactoryBot.define do
  factory :cd_rollout_workflow_token, class: 'Cd::RolloutWorkflowToken' do
    rollout { association(:cd_rollout) }
  end
end
