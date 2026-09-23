# frozen_string_literal: true

FactoryBot.define do
  factory :work_item_decision, class: 'WorkItems::Decision' do
    title { 'Which storage backend should we use?' }
    association :work_item, factory: :work_item
    association :author, factory: :user
    namespace { work_item&.namespace }

    trait :resolved do
      resolved_at { Time.current }
      association :resolved_by, factory: :user
    end

    trait :archived do
      resolved
      archived_at { Time.current }
    end
  end
end
