# frozen_string_literal: true

FactoryBot.define do
  factory :ci_test_balancing_test_split, class: 'Ci::TestBalancing::TestSplit' do
    project
    sequence(:path) { |n| "spec/models/dummy_#{n}_spec.rb" }
  end
end
