# frozen_string_literal: true

FactoryBot.define do
  factory :duo_agent_platform_functional_verification_run,
    class: 'Ai::DuoAgentPlatform::FunctionalVerificationRun' do
    check_type { :agentic_chat }
    status { :running }
    sequence(:workflow_id)

    trait :passed do
      status { :passed }
    end

    trait :failed do
      status { :failed }
      message { 'internal_error · Something went wrong' }
    end
  end
end
