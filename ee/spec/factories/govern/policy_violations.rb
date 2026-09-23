# frozen_string_literal: true

FactoryBot.define do
  factory :govern_policy_violation, class: 'Govern::PolicyViolation' do
    evaluation { association(:govern_policy_evaluation) }
    organization { evaluation.organization }
    policy { evaluation.policy }
  end
end
