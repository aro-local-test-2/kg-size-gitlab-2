# frozen_string_literal: true

module Gitlab
  module Usage
    module Metrics
      module Instrumentations
        # Returns a hash of { event_name => count } for AI audit events
        class CountAiAuditEventsByEventNameClickhouseMetric < GenericMetric
          available? { ::Gitlab::ClickHouse.globally_enabled_for_analytics? }

          def value
            # Re-check the available? condition: Service Ping validation specs force
            # every metric available, bypassing the gate above. Zero counts (not the
            # -1 fallback) keep the value matching the object json schema.
            return empty_counts unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?

            alt_usage_data(fallback: self.class.fallback) do
              rows = ::ClickHouse::Client.select(
                "SELECT event_name, count() AS c FROM ai_audit_events#{time_constraint} GROUP BY event_name", :main
              )

              empty_counts.merge(rows.to_h { |row| [row['event_name'], row['c'].to_i] })
            end
          end

          private

          def time_constraint
            return '' if time_frame == 'all'
            return ' WHERE created_at >= now() - INTERVAL 28 DAY' if time_frame == '28d'

            raise ArgumentError, "Unsupported time_frame: #{time_frame}"
          end

          def empty_counts
            ::AuditEvents::AiAuditEvent::ALLOWED_EVENT_NAMES.index_with(0)
          end
        end
      end
    end
  end
end
