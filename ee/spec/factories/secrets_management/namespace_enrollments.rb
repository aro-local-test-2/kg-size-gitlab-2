# frozen_string_literal: true

FactoryBot.define do
  factory :secrets_manager_namespace_enrollment,
    class: 'SecretsManagement::NamespaceEnrollment' do
    namespace { association(:group) }

    trait :disabled do
      disabled_at { Time.current }
    end

    trait :add_on_requested do
      add_on_requested_at { Time.current }
    end
  end
end
