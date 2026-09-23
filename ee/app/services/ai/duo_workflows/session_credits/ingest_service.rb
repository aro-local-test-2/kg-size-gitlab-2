# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module SessionCredits
      # Fetches per-session GitLab Credits for one namespace's batch of sessions from
      # CustomersDot and writes them to ClickHouse. Re-running is an upsert (the table
      # is a ReplacingMergeTree keyed on workflow_id).
      #
      # This service owns TABLE_NAME for both sides; the GraphQL read path aliases it.
      # Replacement is whole-row, so any second writer (model_used is unfilled today,
      # see https://gitlab.com/gitlab-org/gitlab/-/work_items/592684) must write every
      # column per row, or its inserts win the merge with zeroed credits.
      class IngestService
        TABLE_NAME = 'duo_workflow_session_enrichments'
        MAX_WINDOW_DAYS = 90
        CSV_MAPPING = {
          workflow_id: ->(row) { row[:workflow_id] },
          credits_used: ->(row) { row[:credits_used] },
          updated_at: ->(row) { row[:updated_at] }
        }.freeze
        INSERT_QUERY = <<~SQL.squish
          INSERT INTO #{TABLE_NAME} (#{CSV_MAPPING.keys.join(',')})
          FORMAT CSV
        SQL

        # CustomersDot is degraded (5xx, 429) or has switched the field off on purpose;
        # fanning out more batches would only pile onto it.
        BACKOFF_REASONS = [:server_error, :disabled].freeze

        def initialize(namespace_id:, workflow_ids:)
          @namespace_id = namespace_id
          @workflow_ids = Array(workflow_ids)
        end

        def execute
          return ServiceResponse.success(payload: { rows_written: 0 }) if workflow_ids.empty?

          if namespace_id.nil? && license_key.nil?
            ::Gitlab::AppLogger.warn(
              Labkit::Fields::CLASS_NAME => self.class.name,
              Labkit::Fields::LOG_MESSAGE => 'No billable license to authenticate the CustomersDot request with',
              :workflow_count => workflow_ids.size
            )

            return ServiceResponse.error(
              message: 'No billable license to authenticate the CustomersDot request with',
              reason: :no_billable_license
            )
          end

          begin
            response = client.get_session_credits(workflow_ids: workflow_ids)
          rescue ::Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError => e
            # A GraphQL-level error is about this batch (already in Sentry via the
            # client); it says nothing about CustomersDot's health, so no back-off.
            track_failure(e)
            return ServiceResponse.error(message: 'Failed to fetch session credits from CustomersDot')
          rescue *::Gitlab::HTTP::HTTP_ERRORS => e
            track_failure(e)
            Backoff.record_failure(reason: :connection_error, source: backoff_source)
            return ServiceResponse.error(message: 'Failed to fetch session credits from CustomersDot')
          end

          unless response[:success]
            track_failure

            if BACKOFF_REASONS.include?(response[:reason])
              Backoff.record_failure(reason: response[:reason], source: backoff_source)
            end

            return ServiceResponse.error(
              message: 'CustomersDot could not serve session credits',
              reason: response[:reason]
            )
          end

          Backoff.record_success

          rows = build_rows(response[:sessionCreditsUsed])
          return ServiceResponse.success(payload: { rows_written: 0 }) if rows.empty?

          insert(rows)

          ServiceResponse.success(payload: { rows_written: rows.size })
        end

        private

        attr_reader :namespace_id, :workflow_ids

        # CustomersDot's cost is per subscription, so the root namespace is the unit that
        # fails on .com; self-managed has one subscription, so the batch stands in for it.
        def backoff_source
          namespace_id&.to_s || Digest::SHA256.hexdigest(workflow_ids.map(&:to_i).sort.join(','))
        end

        # Only sessions CustomersDot reported with non-null credits get a row: anything
        # else has no billed credits yet and must read null, not zero. Ids outside the
        # requested batch are dropped: the table is keyed on workflow_id alone, so
        # writing them would land in other sessions' rows.
        def build_rows(session_credits)
          now = Time.current.utc
          requested = workflow_ids.to_set(&:to_i)

          Array(session_credits).filter_map do |entry|
            workflow_id = entry[:workflowId].to_i
            next if workflow_id == 0
            next unless requested.include?(workflow_id)
            next if entry[:creditsUsed].nil?

            {
              workflow_id: workflow_id,
              credits_used: entry[:creditsUsed].to_f,
              updated_at: now.strftime('%Y-%m-%d %H:%M:%S.%6N')
            }
          end
        end

        def insert(rows)
          CsvBuilder::Gzip.new(rows, CSV_MAPPING).render do |tempfile, rows_written|
            next if rows_written == 0

            File.open(tempfile.path) do |file|
              ::ClickHouse::Client.insert_csv(INSERT_QUERY, file, :main)
            end
          end
        end

        # The window must cover every billing event for the batch, not just the
        # transition that triggered the fetch.
        def start_date
          floor = MAX_WINDOW_DAYS.days.ago.to_date
          earliest = ::Ai::DuoWorkflows::Workflow.id_in(workflow_ids).minimum(:created_at)

          return floor unless earliest

          [earliest.to_date, floor].max
        end

        def client
          args = {
            start_date: start_date.iso8601,
            end_date: Date.current.iso8601
          }

          if namespace_id
            args[:namespace_id] = namespace_id
          else
            args[:license_key] = license_key
          end

          ::Gitlab::SubscriptionPortal::SubscriptionUsageClient.new(**args)
        end

        def license_key
          return @license_key if defined?(@license_key)

          @license_key = ::License.billable_license&.data
        end

        # Built inside the method: a class-body gauge is evaluated at constantize
        # time and breaks server_metrics_spec.
        def track_failure(error = nil)
          ::Gitlab::Metrics.counter(
            :duo_workflow_session_credits_fetch_failures_total,
            'Total failed CustomersDot session credit fetches'
          ).increment

          fields = {
            Labkit::Fields::CLASS_NAME => self.class.name,
            Labkit::Fields::LOG_MESSAGE => 'Failed to fetch session credits',
            Labkit::Fields::GL_ROOT_NAMESPACE_ID => namespace_id,
            :workflow_count => workflow_ids.size
          }

          if error
            fields[Labkit::Fields::ERROR_TYPE] = error.class.name
            fields[Labkit::Fields::ERROR_MESSAGE] = error.message
          end

          ::Gitlab::AppLogger.warn(fields)
        end
      end
    end
  end
end
