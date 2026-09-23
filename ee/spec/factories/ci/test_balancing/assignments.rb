# frozen_string_literal: true

FactoryBot.define do
  factory :ci_test_balancing_assignment, class: 'Ci::TestBalancing::Assignment' do
    project
    pipeline factory: :ci_pipeline
    test_split factory: :ci_test_balancing_test_split
    job_group factory: :ci_test_balancing_job_group
    pipeline_created_at { pipeline.created_at }
    expected_duration { 12.5 }
    node_index { 1 }
  end
end
