# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::FetchNamespaceSessionCreditsWorker, :click_house, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  let_it_be(:namespace) { create(:group) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, namespace: namespace) }

  let(:namespace_id) { namespace.id }
  let(:workflow_ids) { [workflow.id] }
  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }

  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(client)
    allow(client).to receive(:get_session_credits).and_return(
      { success: true, sessionCreditsUsed: [{ workflowId: workflow.id.to_s, creditsUsed: 2.5 }] }
    )
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [namespace_id, workflow_ids] }

    it 'serves the same deduplicated row per workflow however many times it runs' do
      perform_idempotent_work

      rows = ClickHouse::Client.select(<<~SQL, :main)
        SELECT workflow_id, argMax(credits_used, updated_at) AS credits_used
        FROM duo_workflow_session_enrichments
        GROUP BY workflow_id
      SQL

      expect(rows).to contain_exactly({ 'workflow_id' => workflow.id, 'credits_used' => 2.5 })
    end
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(namespace_id, workflow_ids) }

    it 'delegates to the ingest service' do
      service = instance_double(Ai::DuoWorkflows::SessionCredits::IngestService)

      expect(Ai::DuoWorkflows::SessionCredits::IngestService).to receive(:new)
        .with(namespace_id: namespace_id, workflow_ids: workflow_ids).and_return(service)
      expect(service).to receive(:execute).and_return(ServiceResponse.success(payload: { rows_written: 1 }))

      perform
    end

    context 'when ClickHouse analytics is disabled' do
      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      end

      it 'does not call the ingest service' do
        expect(Ai::DuoWorkflows::SessionCredits::IngestService).not_to receive(:new)

        perform
      end
    end

    context 'when the ingestion flag is disabled' do
      before do
        stub_feature_flags(duo_workflow_session_credits_ingestion: false)
      end

      it 'does not call the ingest service, so flipping the flag stops buffered jobs' do
        expect(Ai::DuoWorkflows::SessionCredits::IngestService).not_to receive(:new)

        perform
      end
    end

    context 'when the ingestion flag is enabled for a group only' do
      before do
        stub_feature_flags(duo_workflow_session_credits_ingestion: namespace)
      end

      it 'calls the ingest service for a batch in that group' do
        expect(Ai::DuoWorkflows::SessionCredits::IngestService).to receive(:new).and_call_original

        perform
      end

      context 'when the batch belongs to another group' do
        let(:namespace_id) { create(:group).id }

        it 'does not call the ingest service' do
          expect(Ai::DuoWorkflows::SessionCredits::IngestService).not_to receive(:new)

          perform
        end
      end

      context 'when the batch is instance-level' do
        let(:namespace_id) { nil }

        it 'does not call the ingest service' do
          expect(Ai::DuoWorkflows::SessionCredits::IngestService).not_to receive(:new)

          perform
        end
      end
    end

    context 'when backing off from a CustomersDot degradation' do
      before do
        Ai::DuoWorkflows::SessionCredits::Backoff.trigger!(reason: :server_error)
      end

      it 'raises for retry without calling CustomersDot, so buffered batches wait with the cron' do
        expect(Ai::DuoWorkflows::SessionCredits::IngestService).not_to receive(:new)

        expect { perform }.to raise_error(described_class::FetchError)
      end
    end

    context 'when the kill switch latch is set' do
      before do
        Ai::DuoWorkflows::SessionCredits::Backoff.trigger!(reason: :disabled)
      end

      it 'still probes CustomersDot, since a success is what lifts that latch' do
        expect(Ai::DuoWorkflows::SessionCredits::IngestService).to receive(:new).and_call_original

        perform
      end
    end

    context 'when the ingest service reports a failure' do
      let(:service) { instance_double(Ai::DuoWorkflows::SessionCredits::IngestService) }

      before do
        allow(Ai::DuoWorkflows::SessionCredits::IngestService).to receive(:new).and_return(service)
      end

      it 'raises so Sidekiq retries the batch' do
        allow(service).to receive(:execute)
          .and_return(ServiceResponse.error(message: 'Failed to fetch session credits from CustomersDot'))

        expect { perform }.to raise_error(described_class::FetchError)
      end

      it 'does not raise when there is no billable license, which retries cannot fix' do
        allow(service).to receive(:execute)
          .and_return(ServiceResponse.error(message: 'No billable license', reason: :no_billable_license))

        expect { perform }.not_to raise_error
      end

      it 'raises for the kill switch and server errors, which do recover' do
        [:disabled, :server_error].each do |reason|
          allow(service).to receive(:execute)
            .and_return(ServiceResponse.error(message: 'CustomersDot could not serve session credits', reason: reason))

          expect { perform }.to raise_error(described_class::FetchError)
        end
      end

      it 'does not raise while CustomersDot does not expose the field yet' do
        allow(service).to receive(:execute)
          .and_return(ServiceResponse.error(
            message: 'CustomersDot could not serve session credits', reason: :undefined_field
          ))

        expect { perform }.not_to raise_error
      end
    end
  end

  describe '.sidekiq_retry_in' do
    let(:backoff) { Ai::DuoWorkflows::SessionCredits::Backoff::BACKOFF_DURATION.to_i }

    it 'waits out the back-off window before retrying a failed fetch' do
      delay = described_class.sidekiq_retry_in_block.call(0, described_class::FetchError.new)

      expect(delay).to be_between(backoff, 2 * backoff)
    end

    it 'floors every error at the window, since any retry re-queries CustomersDot' do
      delay = described_class.sidekiq_retry_in_block.call(0, StandardError.new)

      expect(delay).to be_between(backoff, 2 * backoff)
    end

    it "keeps Sidekiq's exponential spacing once it exceeds the window" do
      delay = described_class.sidekiq_retry_in_block.call(10, described_class::FetchError.new)

      expect(delay).to be >= (10**4) + 15
    end

    it 'waits out an escalated latch rather than the base window' do
      Ai::DuoWorkflows::SessionCredits::Backoff.trigger!(reason: :server_error)
      Gitlab::Redis::SharedState.with do |redis|
        redis.expire(Ai::DuoWorkflows::SessionCredits::Backoff::LATCH_KEY, 2.hours.to_i)
      end

      delay = described_class.sidekiq_retry_in_block.call(0, described_class::FetchError.new)

      expect(delay).to be_between(2.hours.to_i - 30, 2.hours.to_i + backoff)
    end

    it 'keeps the base window when the latch has less than that left' do
      Ai::DuoWorkflows::SessionCredits::Backoff.trigger!(reason: :server_error)
      Gitlab::Redis::SharedState.with do |redis|
        redis.expire(Ai::DuoWorkflows::SessionCredits::Backoff::LATCH_KEY, 10.minutes.to_i)
      end

      delay = described_class.sidekiq_retry_in_block.call(0, described_class::FetchError.new)

      expect(delay).to be_between(backoff, 2 * backoff)
    end
  end

  describe '.sidekiq_retries_exhausted' do
    it 'logs the dropped batch with its workflow ids' do
      job = { 'args' => [namespace_id, workflow_ids] }

      expect(Gitlab::AppLogger).to receive(:error).with(hash_including(
        Labkit::Fields::GL_ROOT_NAMESPACE_ID => namespace_id,
        :workflow_ids => workflow_ids
      ))

      described_class.sidekiq_retries_exhausted_block.call(job)
    end
  end

  it 'registers with ClickHouse migration pause control' do
    expect(described_class.click_house_worker_attrs).to be_present
  end

  it 'keeps the full default retry budget, since exhausting it drops the batch for good' do
    # true means Sidekiq's default of 25 attempts, not a GitLab override.
    expect(described_class.get_sidekiq_options['retry']).to be(true)
  end

  it 'bounds outbound CustomersDot pressure with a concurrency limit' do
    # get_concurrency_limit short-circuits to 0 when this ops flag is off
    # (app/workers/concerns/worker_attributes.rb:217), so stub it or the example
    # can go green for the wrong reason.
    stub_feature_flags(sidekiq_concurrency_limit_middleware: true)

    expect(described_class.get_concurrency_limit).to eq(5)
  end
end
