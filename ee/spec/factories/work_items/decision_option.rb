# frozen_string_literal: true

FactoryBot.define do
  factory :work_item_decision_option, class: 'WorkItems::DecisionOption' do
    association :decision, factory: :work_item_decision

    content { 'Use PostgreSQL' }
    namespace { decision&.namespace }

    trait :recommended do
      recommended { true }
      description { 'Recommended because it matches the existing stack' }
    end

    trait :selected do
      selected { true }
    end
  end
end
