# frozen_string_literal: true

module Utilization
  module BillableUsage
    class DailyAggregate < ApplicationRecord
      self.table_name = 'billable_usage_daily_aggregates'

      # Ceiling imposed by the `com.gitlab/billable_usage` Iglu schema in gitlab-org/iglu,
      # which caps `quantity` at this value in every version. A record exceeding it cannot
      # be exported.
      MAX_QUANTITY = 2_147_483_647

      validates :event_aggregate_uuid, :usage_date, :event_type, :unit_of_measure, :feature_qualified_name,
        :quantity, :events_count, presence: true
      validates :quantity, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_QUANTITY }
      validates :events_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }
      validates :event_type, :feature_qualified_name, length: { maximum: 255 }
      validates :unit_of_measure, length: { maximum: 64 }
      validates :operation_type, length: { maximum: 64 }, allow_nil: true
    end
  end
end
