# frozen_string_literal: true

module Gitlab
  module Usage
    module Metrics
      module Instrumentations
        # Returns a hash of { event_name => count } for AI audit events.
        class CountAiAuditEventsByEventNameMetric < DatabaseMetric
          operation :count

          relation { ::AuditEvents::AiAuditEvent.group(:event_name) }

          timestamp_column :created_at

          def value
            grouped = super

            # `super` may return -1 when there's an underlying failure (statement timeout, etc)
            grouped.is_a?(Hash) ? empty_counts.merge(grouped) : grouped
          end

          private

          def empty_counts
            ::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES.index_with(0)
          end
        end
      end
    end
  end
end
