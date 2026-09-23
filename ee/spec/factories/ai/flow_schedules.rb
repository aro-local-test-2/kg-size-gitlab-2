# frozen_string_literal: true

FactoryBot.define do
  factory :ai_flow_schedule, class: '::Ai::FlowSchedule' do
    flow_trigger factory: :ai_flow_trigger
    project { flow_trigger.project }
    cron { '0 9 * * 1' }
    cron_timezone { 'UTC' }
    sequence(:description) { |n| "schedule #{n}" }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :deactivated_by_failures do
      active { false }
      consecutive_failure_count { Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES }
      last_run_status { :sa_invalid }
      last_run_error { 'Service account is no longer available' }
    end
  end
end
