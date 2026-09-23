# frozen_string_literal: true

FactoryBot.define do
  factory :billable_usage_daily_aggregate, class: 'Utilization::BillableUsage::DailyAggregate' do
    event_aggregate_uuid { SecureRandom.uuid }
    usage_date { Date.current }
    event_type { 'secrets_read' }
    unit_of_measure { 'request' }
    feature_qualified_name { 'secrets_read' }
    quantity { 1 }
    events_count { 1 }

    trait :gauge do
      event_type { 'secrets_stored' }
      unit_of_measure { 'secret' }
      feature_qualified_name { 'secrets_stored' }
    end
  end
end
