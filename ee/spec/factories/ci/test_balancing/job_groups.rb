# frozen_string_literal: true

FactoryBot.define do
  factory :ci_test_balancing_job_group, class: 'Ci::TestBalancing::JobGroup' do
    project
    sequence(:name) { |n| "rspec-#{n} unit pg17" }
  end
end
