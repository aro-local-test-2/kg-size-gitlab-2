# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCredits::IngestService, :click_house, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  let_it_be(:namespace) { create(:group) }
  let_it_be(:workflow_a) { create(:duo_workflows_workflow, namespace: namespace, created_at: 10.days.ago) }
  let_it_be(:workflow_b) { create(:duo_workflows_workflow, namespace: namespace, created_at: 40.days.ago) }

  let(:workflow_ids) { [workflow_a.id, workflow_b.id] }
  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }
  let(:response) do
    {
      success: true,
      sessionCreditsUsed: [
        { workflowId: workflow_a.id.to_s, creditsUsed: 12.5 },
        { workflowId: workflow_b.id.to_s, creditsUsed: 3.0 }
      ]
    }
  end

  subject(:execute) { described_class.new(namespace_id: namespace.id, workflow_ids: workflow_ids).execute }

  before do
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(client)
    allow(client).to receive(:get_session_credits).and_return(response)
  end

  def enrichment_rows
    ClickHouse::Client.select(
      'SELECT workflow_id, credits_used FROM duo_workflow_session_enrichments ORDER BY workflow_id', :main
    )
  end

  it 'lifts a kill-switch latch on success, since the field is evidently back on' do
    Ai::DuoWorkflows::SessionCredits::Backoff.trigger!(reason: :disabled)

    execute

    expect(Ai::DuoWorkflows::SessionCredits::Backoff.active?).to be(false)
  end

  it 'leaves a degradation latch to expire on its own, so one success cannot flap the cron' do
    Ai::DuoWorkflows::SessionCredits::Backoff.trigger!(reason: :server_error)

    execute

    expect(Ai::DuoWorkflows::SessionCredits::Backoff.reason).to eq(:server_error)
  end

  it 'inserts one row per returned session' do
    expect { execute }.to change { enrichment_rows.count }.by(2)
  end

  it 'writes the credit totals as floats' do
    execute

    expect(enrichment_rows).to contain_exactly(
      { 'workflow_id' => workflow_a.id, 'credits_used' => 12.5 },
      { 'workflow_id' => workflow_b.id, 'credits_used' => 3.0 }
    )
  end

  it 'reports how many rows it wrote' do
    expect(execute).to be_success
    expect(execute.payload[:rows_written]).to eq(2)
  end

  it 'spans the window back to the earliest created_at in the batch' do
    expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
      .with(hash_including(start_date: workflow_b.created_at.to_date.iso8601)).and_return(client)

    execute
  end

  context 'when the earliest created_at is older than 90 days' do
    let_it_be(:ancient) { create(:duo_workflows_workflow, namespace: namespace, created_at: 200.days.ago) }

    let(:workflow_ids) { [ancient.id] }
    let(:response) { { success: true, sessionCreditsUsed: [] } }

    it 'clamps the window to 90 days' do
      expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
        .with(hash_including(start_date: 90.days.ago.to_date.iso8601)).and_return(client)

      execute
    end
  end

  context 'when a requested session is absent from the response' do
    let(:response) { { success: true, sessionCreditsUsed: [{ workflowId: workflow_a.id.to_s, creditsUsed: 1.0 }] } }

    it 'writes no row for it rather than synthesising zero' do
      execute

      expect(enrichment_rows.map { |r| r['workflow_id'] }).to contain_exactly(workflow_a.id)
    end
  end

  context 'when CustomersDot echoes a session with null credits' do
    let(:response) do
      {
        success: true,
        sessionCreditsUsed: [
          { workflowId: workflow_a.id.to_s, creditsUsed: nil },
          { workflowId: workflow_b.id.to_s, creditsUsed: 3.0 }
        ]
      }
    end

    it 'writes no row for it rather than coercing null to zero' do
      execute

      expect(enrichment_rows.map { |r| r['workflow_id'] }).to contain_exactly(workflow_b.id)
    end
  end

  context 'when CustomersDot returns an id outside the requested batch' do
    let(:workflow_ids) { [workflow_a.id] }
    let(:response) do
      {
        success: true,
        sessionCreditsUsed: [
          { workflowId: workflow_a.id.to_s, creditsUsed: 1.0 },
          { workflowId: workflow_b.id.to_s, creditsUsed: 5.0 }
        ]
      }
    end

    it "drops it rather than writing into another session's row" do
      execute

      expect(enrichment_rows.map { |r| r['workflow_id'] }).to contain_exactly(workflow_a.id)
    end
  end

  context 'when the response is empty' do
    let(:response) { { success: true, sessionCreditsUsed: [] } }

    it 'writes nothing and succeeds' do
      expect { execute }.not_to change { enrichment_rows.count }
      expect(execute).to be_success
    end
  end

  context 'when workflow_ids is empty' do
    let(:workflow_ids) { [] }

    it 'does not call CustomersDot at all' do
      expect(client).not_to receive(:get_session_credits)
      expect(execute).to be_success
    end
  end

  context 'when the CustomersDot call fails' do
    # get_session_credits RAISES rather than returning an error hash: error(query, response)
    # goes through Gitlab::ErrorTracking.track_and_raise_exception.
    before do
      allow(client).to receive(:get_session_credits)
        .and_raise(Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)
    end

    it 'returns an error and writes nothing' do
      expect { execute }.not_to change { enrichment_rows.count }
      expect(execute).to be_error
    end

    it 'does not count towards back-off: a GraphQL-level error is one batch, not an outage' do
      expect(Ai::DuoWorkflows::SessionCredits::Backoff).not_to receive(:record_failure)

      execute
    end

    it 'increments the failure counter' do
      counter = instance_double(Prometheus::Client::Counter, increment: true)
      allow(Gitlab::Metrics).to receive(:counter).and_return(counter)

      expect(counter).to receive(:increment)

      execute
    end
  end

  context 'when the client reports an unsuccessful response' do
    let(:response) { { success: false, sessionCreditsUsed: nil } }

    it 'returns an error and writes nothing' do
      expect { execute }.not_to change { enrichment_rows.count }
      expect(execute).to be_error
    end

    it 'does not count towards back-off, since the failure is not a CustomersDot outage' do
      expect(Ai::DuoWorkflows::SessionCredits::Backoff).not_to receive(:record_failure)

      execute
    end

    it 'does not count permanent reasons towards back-off either' do
      expect(Ai::DuoWorkflows::SessionCredits::Backoff).not_to receive(:record_failure)

      [:no_billable_license, :undefined_field].each do |reason|
        allow(client).to receive(:get_session_credits)
          .and_return({ success: false, reason: reason, sessionCreditsUsed: nil })

        # A fresh service each time: the memoized subject would only run the first reason.
        result = described_class.new(namespace_id: namespace.id, workflow_ids: workflow_ids).execute

        expect(result.reason).to eq(reason)
      end
    end
  end

  # Frozen so the distinct-failure calls below cannot straddle a 15-minute bucket.
  context 'when CustomersDot answers with a server error', :freeze_time do
    let(:response) { { success: false, reason: :server_error, sessionCreditsUsed: nil } }

    it 'returns the reason so the worker retries' do
      expect(execute).to be_error
      expect(execute.reason).to eq(:server_error)
    end

    it 'records a degradation failure for this batch' do
      expect(Ai::DuoWorkflows::SessionCredits::Backoff)
        .to receive(:record_failure).with(reason: :server_error, source: namespace.id.to_s)

      execute
    end

    it 'does not latch while one namespace keeps failing, since its batches and retries are one source' do
      3.times { described_class.new(namespace_id: namespace.id, workflow_ids: workflow_ids).execute }
      described_class.new(namespace_id: namespace.id, workflow_ids: [workflow_a.id]).execute

      expect(Ai::DuoWorkflows::SessionCredits::Backoff.active?).to be(false)
    end

    it 'latches once distinct namespaces fail, which is an outage rather than one heavy subscription' do
      [namespace, create(:group), create(:group)].each do |group|
        described_class.new(namespace_id: group.id, workflow_ids: workflow_ids).execute
      end

      expect(Ai::DuoWorkflows::SessionCredits::Backoff.reason).to eq(:server_error)
    end

    it 'increments the failure counter' do
      counter = instance_double(Prometheus::Client::Counter, increment: true)
      allow(Gitlab::Metrics).to receive(:counter).and_return(counter)

      expect(counter).to receive(:increment)

      execute
    end
  end

  context 'when CustomersDot has disabled the field' do
    let(:response) { { success: false, reason: :disabled, sessionCreditsUsed: nil } }

    it 'returns the reason so the worker keeps retrying' do
      expect(execute).to be_error
      expect(execute.reason).to eq(:disabled)
    end

    it 'triggers the long back-off so the cron stops fanning out against the kill switch' do
      execute

      expect(Ai::DuoWorkflows::SessionCredits::Backoff.reason).to eq(:disabled)
    end
  end

  context 'when the CustomersDot call fails at the connection level' do
    before do
      allow(client).to receive(:get_session_credits).and_raise(Net::ReadTimeout)
    end

    it 'returns an error and writes nothing' do
      expect { execute }.not_to change { enrichment_rows.count }
      expect(execute).to be_error
    end

    it 'records a degradation failure for this batch' do
      expect(Ai::DuoWorkflows::SessionCredits::Backoff)
        .to receive(:record_failure).with(reason: :connection_error, source: namespace.id.to_s)

      execute
    end

    it 'increments the failure counter' do
      counter = instance_double(Prometheus::Client::Counter, increment: true)
      allow(Gitlab::Metrics).to receive(:counter).and_return(counter)

      expect(counter).to receive(:increment)

      execute
    end
  end

  context 'when there is no namespace_id (self-managed)' do
    let(:license) { instance_double(License, data: 'license-data') }

    before do
      allow(License).to receive(:billable_license).and_return(license)
    end

    it 'authenticates with the license key instead' do
      expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
        .with(hash_including(license_key: 'license-data')).and_return(client)

      described_class.new(namespace_id: nil, workflow_ids: workflow_ids).execute
    end

    it 'reports failures to the back-off per batch, since there is one subscription to key on' do
      allow(client).to receive(:get_session_credits)
        .and_return({ success: false, reason: :server_error, sessionCreditsUsed: nil })

      expect(Ai::DuoWorkflows::SessionCredits::Backoff)
        .to receive(:record_failure).with(reason: :server_error, source: a_string_matching(/\A\h{64}\z/))

      described_class.new(namespace_id: nil, workflow_ids: workflow_ids).execute
    end
  end

  context 'when there is no namespace_id and no billable license' do
    before do
      allow(License).to receive(:billable_license).and_return(nil)
    end

    it 'fails fast instead of degrading to an unauthenticated request' do
      result = described_class.new(namespace_id: nil, workflow_ids: workflow_ids).execute

      expect(result).to be_error
      expect(result.reason).to eq(:no_billable_license)
      expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).not_to have_received(:new)
    end
  end
end
