# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BillingEvents::Client, :freeze_time, feature_category: :application_instrumentation do
  let_it_be(:namespace) { create(:group) }

  let(:args) do
    {
      event_type: 'secrets_read',
      category: 'TestCategory',
      unit_of_measure: 'request',
      quantity: 1,
      namespace: namespace
    }
  end

  before do
    allow(Gitlab::Tracking).to receive(:billing_event)
  end

  def tracked_data
    data = nil

    expect(Gitlab::Tracking).to have_received(:billing_event) do |_cat, _action, context:|
      data = context.first.to_json[:data]
    end

    data
  end

  describe 'secrets_read billing metrics', :clean_gitlab_redis_shared_state do
    subject(:track) { described_class.new.track_billing_event(**args) }

    it 'increments the secrets_read billing metrics' do
      expect { track }
        .to increment_usage_metrics(
          'counts.count_total_usage_billing_event_secrets_read',
          'counts.count_total_usage_billing_event_secrets_read_weekly',
          'counts.count_total_usage_billing_event_secrets_read_monthly'
        )
    end
  end

  describe 'secrets_stored billing metrics', :clean_gitlab_redis_shared_state do
    subject(:track) { described_class.new.track_billing_event(**args) }

    let(:args) do
      {
        event_type: 'secrets_stored',
        category: 'TestCategory',
        unit_of_measure: 'secret',
        quantity: 5,
        namespace: namespace
      }
    end

    it 'increments the secrets_stored billing metrics' do
      expect { track }
        .to increment_usage_metrics(
          'counts.count_total_usage_billing_event_secrets_stored',
          'counts.count_total_usage_billing_event_secrets_stored_weekly',
          'counts.count_total_usage_billing_event_secrets_stored_monthly'
        )
    end
  end

  describe 'realm mapping' do
    using RSpec::Parameterized::TableSyntax

    where(:cloud_connector_realm, :expected_realm) do
      'saas'         | 'SaaS'
      'self-managed' | 'SM'
      'dedicated'    | 'Dedicated'
    end

    with_them do
      before do
        allow(CloudConnector).to receive(:gitlab_realm).and_return(cloud_connector_realm)
      end

      it 'maps to the billing schema realm value' do
        described_class.new.track_billing_event(**args)

        expect(tracked_data[:realm]).to eq(expected_realm)
      end
    end
  end

  describe 'deployment_type' do
    before do
      allow(CloudConnector).to receive(:deployment_type).and_return('.com')
    end

    it 'uses CloudConnector deployment_type' do
      described_class.new.track_billing_event(**args)

      expect(tracked_data[:deployment_type]).to eq('.com')
    end
  end

  describe 'unique_instance_id' do
    let(:cdot_instance_uid) { 'a3c1b8e2-8ea1-4a3f-9c1a-2d7b6f2c9e11' }
    let(:derived_instance_uuid) { Gitlab::GlobalAnonymousId.instance_uuid }
    let(:token_claims) do
      { 'sub' => 'instance-uuid', 'gitlab_instance_uid' => cdot_instance_uid, 'exp' => 1.hour.from_now.to_i }
    end

    let(:cloud_connector_token) { JWT.encode(token_claims, nil, 'none') }

    subject(:track) { described_class.new.track_billing_event(**args.merge(idempotency_key: 'secrets_read:req-1')) }

    before do
      Gitlab::ProcessMemoryCache.cache_backend.delete(described_class::INSTANCE_UID_CACHE_KEY)
      allow(CloudConnector::Tokens).to receive(:cloud_connector_token).and_return(cloud_connector_token)
    end

    shared_examples 'falls back to the instance-derived uuid' do
      it 'sends Gitlab::GlobalAnonymousId.instance_uuid' do
        track

        expect(tracked_data[:unique_instance_id]).to eq(derived_instance_uuid)
      end
    end

    context 'on a self-managed instance' do
      before do
        allow(CloudConnector).to receive(:gitlab_realm).and_return(CloudConnector::GITLAB_REALM_SELF_MANAGED)
      end

      it 'sends the gitlab_instance_uid claim of the Cloud Connector token', :aggregate_failures do
        track

        data = tracked_data
        expect(data[:unique_instance_id]).to eq(cdot_instance_uid)
        expect(data[:instance_id]).to eq(Gitlab::GlobalAnonymousId.instance_id)
      end

      it 'keeps deriving the event_id from the instance-derived uuid' do
        track

        expect(tracked_data[:event_id])
          .to eq(Digest::UUID.uuid_v5(derived_instance_uuid, 'secrets_read:req-1'))
      end

      it 'reads the token once and caches the claim across client instances' do
        3.times { described_class.new.track_billing_event(**args) }

        expect(CloudConnector::Tokens).to have_received(:cloud_connector_token).once
        expect(Gitlab::Tracking).to have_received(:billing_event).exactly(3).times do |_cat, _action, context:|
          expect(context.first.to_json[:data][:unique_instance_id]).to eq(cdot_instance_uid)
        end
      end

      it 'reads the token again once the cache expires' do
        described_class.new.track_billing_event(**args)
        travel(described_class::INSTANCE_UID_CACHE_TTL + 1.second)
        described_class.new.track_billing_event(**args)

        expect(CloudConnector::Tokens).to have_received(:cloud_connector_token).twice
      end

      context 'when the token has no gitlab_instance_uid claim' do
        let(:token_claims) { { 'sub' => 'instance-uuid', 'exp' => 1.hour.from_now.to_i } }

        it_behaves_like 'falls back to the instance-derived uuid'
      end

      context 'when the claim is blank' do
        let(:token_claims) { { 'gitlab_instance_uid' => '', 'exp' => 1.hour.from_now.to_i } }

        it_behaves_like 'falls back to the instance-derived uuid'
      end

      context 'when no Cloud Connector token is available' do
        let(:cloud_connector_token) { nil }

        it_behaves_like 'falls back to the instance-derived uuid'

        it 'does not report an error' do
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

          track
        end

        it 'does not cache the missing claim' do
          2.times { described_class.new.track_billing_event(**args) }

          expect(CloudConnector::Tokens).to have_received(:cloud_connector_token).twice
        end
      end

      context 'when the token cannot be decoded' do
        let(:cloud_connector_token) { 'not-a-jwt' }

        it_behaves_like 'falls back to the instance-derived uuid'

        it 'reports the error without failing the event' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(JWT::DecodeError),
            hash_including(message: a_string_including('Cloud Connector token'))
          )

          track

          expect(Gitlab::Tracking).to have_received(:billing_event)
        end
      end
    end

    context 'on GitLab.com' do
      before do
        allow(CloudConnector).to receive(:gitlab_realm).and_return(CloudConnector::GITLAB_REALM_SAAS)
      end

      it_behaves_like 'falls back to the instance-derived uuid'

      it 'does not read the Cloud Connector token' do
        track

        expect(CloudConnector::Tokens).not_to have_received(:cloud_connector_token)
      end
    end
  end

  describe '#local_persistence_enabled?' do
    subject { described_class.new.local_persistence_enabled? }

    context 'when the local_billing_persistence feature flag is disabled' do
      before do
        stub_feature_flags(local_billing_persistence: false)

        license = create(:license)
        allow(License).to receive(:current).and_return(license)
        allow(license).to receive(:offline_cloud_license?).and_return(true)
      end

      it 'returns false regardless of the licence' do
        is_expected.to be(false)
      end
    end

    context 'when the local_billing_persistence feature flag is enabled' do
      context 'and the licence is not an offline cloud licence' do
        before do
          license = create(:license)
          allow(License).to receive(:current).and_return(license)
          allow(license).to receive(:offline_cloud_license?).and_return(false)
        end

        it 'returns false' do
          is_expected.to be(false)
        end
      end

      context 'and the licence is an offline cloud licence' do
        before do
          license = create(:license)
          allow(License).to receive(:current).and_return(license)
          allow(license).to receive(:offline_cloud_license?).and_return(true)
        end

        it 'returns true' do
          is_expected.to be(true)
        end

        context 'and the instance is SaaS', :saas do
          it 'returns false, so the aggregate table is never written on .com' do
            is_expected.to be(false)
          end
        end
      end
    end
  end

  describe 'local persistence of billing events' do
    context 'when local persistence is enabled' do
      before do
        license = create(:license)
        allow(License).to receive(:current).and_return(license)
        allow(license).to receive(:offline_cloud_license?).and_return(true)
      end

      it 'persists the event locally instead of emitting it', :aggregate_failures do
        expect_next_instance_of(Utilization::BillableUsage::RecordAggregateService) do |service|
          expect(service).to receive(:execute)
        end

        described_class.new.track_billing_event(**args)

        expect(Gitlab::Tracking).not_to have_received(:billing_event)
      end

      # Only emission is replaced. The internal event feeds Service Ping and local
      # counters, which work without connectivity, so air-gapped must not lose it.
      it 'still tracks the internal event' do
        expect(Gitlab::InternalEvents).to receive(:track_event).with(
          'usage_billing_event', hash_including(category: args[:category])
        )

        described_class.new.track_billing_event(**args)
      end

      # The snapshot entry point has to carry its quantity kind all the way to the
      # aggregate, otherwise a repeated reading would accumulate. Summing these two
      # would give 2312 rather than superseding to 1162.
      it 'supersedes the quantity when the same snapshot is taken again' do
        snapshot_args = args.merge(
          event_type: 'secrets_stored',
          unit_of_measure: 'secret',
          metadata: { feature_qualified_name: 'secrets_stored' }
        )

        described_class.new.track_billing_snapshot(**snapshot_args.merge(quantity: 1150))
        described_class.new.track_billing_snapshot(**snapshot_args.merge(quantity: 1162))

        aggregate = Utilization::BillableUsage::DailyAggregate.find_by!(event_type: 'secrets_stored')

        expect(aggregate).to have_attributes(quantity: 1162, events_count: 2)
      end
    end

    context 'when local persistence is disabled' do
      before do
        stub_feature_flags(local_billing_persistence: false)
      end

      it 'emits the event and does not persist it locally', :aggregate_failures do
        expect(Utilization::BillableUsage::RecordAggregateService).not_to receive(:new)

        described_class.new.track_billing_event(**args)

        expect(Gitlab::Tracking).to have_received(:billing_event)
      end
    end
  end
end
