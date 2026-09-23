# frozen_string_literal: true

module Gitlab
  module Usage
    module Metrics
      module Instrumentations
        # Counts distinct AI agent sessions (workflows) with AI audit events stored
        # in ClickHouse, the counterpart to
        # CountDistinctAiAgentSessionsWithAuditEventsMetric (PostgreSQL fallback store).
        class CountDistinctAiAgentSessionsWithAuditEventsClickhouseMetric < GenericMetric
          # Only instances using ClickHouse analytics write audit events to
          # ClickHouse, so skip this metric elsewhere (see
          # CountAiAuditEventsClickhouseMetric for the full rationale).
          available? { ::Gitlab::ClickHouse.globally_enabled_for_analytics? }

          def value
            # Re-check the available? condition: Service Ping validation specs force
            # every metric available, bypassing the gate above.
            return self.class.fallback unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?

            alt_usage_data(fallback: self.class.fallback) do
              ::ClickHouse::Client.select(
                "SELECT uniqExact(workflow_id) AS c FROM ai_audit_events#{time_constraint}", :main
              ).first&.fetch('c', 0).to_i
            end
          end

          private

          def time_constraint
            return '' if time_frame == 'all'
            return ' WHERE created_at >= now() - INTERVAL 28 DAY' if time_frame == '28d'

            raise ArgumentError, "Unsupported time_frame: #{time_frame}"
          end
        end
      end
    end
  end
end
