# frozen_string_literal: true

FactoryBot.define do
  factory :govern_policy_evaluation, class: 'Govern::PolicyEvaluation' do
    policy { association(:govern_policy) }
    organization { policy.organization }
    trigger_type { :deployment_requested }
    mode { :enforce }
    verdict { :allow }
    policy_version { 1 }
    evaluated_at { Time.current }
  end
end
