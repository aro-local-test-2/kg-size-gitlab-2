# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::PushGateDecisionService, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }
  let_it_be(:user) { create(:user) }

  let(:rollout) do
    create(:cd_rollout, version_set: version_set, application: application, state: :in_progress, workflow_ref: 'wf-1')
  end

  let(:result) { 'approve' }
  let(:request_approval_step) { nil }

  let!(:request_approval_transition) do
    create(:cd_rollout_transition, rollout: rollout, event: 'request_approval',
      from_state: 'in_progress', to_state: 'in_progress', rollout_step: request_approval_step)
  end

  subject(:service) do
    described_class.new(rollout, request_transition: request_approval_transition, result: result, current_user: user)
  end

  describe '#execute' do
    context 'when no channel token exists for the rollout' do
      it 'does not attempt to contact KAS' do
        expect(Gitlab::Kas::Client).not_to receive(:new)

        service.execute
      end
    end

    context 'when a channel token exists for the rollout' do
      let(:kas_client) { instance_double(Gitlab::Kas::Client) }

      let(:request_approval_step) do
        create(:cd_rollout_step, rollout: rollout, path: '0.1', step_type: Cd::RolloutStep::APPROVAL_STEP_TYPE)
      end

      let!(:channel_token) do
        create(:cd_rollout_channel_token, rollout: rollout, token: 'a-token', rollout_step: request_approval_step)
      end

      let!(:workflow_token) do
        create(:cd_rollout_workflow_token, rollout: rollout, token: 'wf-token')
      end

      before do
        allow(Gitlab::Kas::Client).to receive(:new).and_return(kas_client)
      end

      it 'pushes the decision to the workflow with the expected shape' do
        expect(kas_client).to receive(:send_to_workflow_channel).with(
          idempotency_key: "rollout-gate:#{rollout.id}:0.1:#{request_approval_transition.id}:approve",
          channel_token: 'a-token',
          workflow_token: 'wf-token',
          value: {
            'position' => [0, 1],
            'result' => 'approve',
            'actor' => { 'name' => user.name, 'id' => user.id }
          }
        )

        service.execute
      end

      it 'produces a distinct idempotency key for a second approval at the same step position' do
        idempotency_keys = []
        allow(kas_client).to receive(:send_to_workflow_channel) do |args|
          idempotency_keys << args[:idempotency_key]
        end

        service.execute

        other_transition = create(:cd_rollout_transition, rollout: rollout, event: 'request_approval',
          from_state: 'in_progress', to_state: 'in_progress', rollout_step: request_approval_step)
        described_class.new(
          rollout, request_transition: other_transition, result: result, current_user: user
        ).execute

        expect(idempotency_keys.size).to eq(2)
        expect(idempotency_keys[0]).not_to eq(idempotency_keys[1])
      end

      context 'when a channel token exists for a different step' do
        let!(:other_channel_token) do
          other_step = create(:cd_rollout_step, rollout: rollout, path: '0.2')
          create(:cd_rollout_channel_token, rollout: rollout, token: 'other-token', rollout_step: other_step)
        end

        it "still uses the token that matches this gate's own step" do
          expect(kas_client).to receive(:send_to_workflow_channel).with(hash_including(channel_token: 'a-token'))

          service.execute
        end
      end

      context 'when the gate was not opened for a step' do
        let(:request_approval_step) { nil }
        let!(:channel_token) { create(:cd_rollout_channel_token, rollout: rollout, token: 'a-token') }

        it 'sends an empty position' do
          expect(kas_client).to receive(:send_to_workflow_channel).with(
            hash_including(
              idempotency_key: "rollout-gate:#{rollout.id}::#{request_approval_transition.id}:approve",
              value: hash_including('position' => [])
            )
          )

          service.execute
        end
      end

      context "when no channel token matches this gate's step" do
        let!(:channel_token) { create(:cd_rollout_channel_token, rollout: rollout, token: 'a-token') }

        it 'does not attempt to contact KAS' do
          expect(Gitlab::Kas::Client).not_to receive(:new)

          service.execute
        end
      end

      context 'when no workflow token exists for the rollout' do
        let!(:workflow_token) { nil }

        it 'does not attempt to contact KAS' do
          expect(Gitlab::Kas::Client).not_to receive(:new)

          service.execute
        end
      end

      context 'when send_to_workflow_channel raises a gRPC error' do
        before do
          allow(kas_client).to receive(:send_to_workflow_channel).and_raise(GRPC::NotFound.new('gone'))
        end

        it 'logs the exception instead of raising' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            instance_of(GRPC::NotFound), rollout_id: rollout.id, channel_name: channel_token.channel_name
          )

          expect { service.execute }.not_to raise_error
        end
      end

      context 'when KAS is not configured on this instance' do
        before do
          allow(Gitlab::Kas::Client).to receive(:new)
            .and_raise(Gitlab::Kas::Client::ConfigurationError, 'GitLab KAS is not enabled')
        end

        it 'logs the exception instead of raising' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            instance_of(Gitlab::Kas::Client::ConfigurationError),
            rollout_id: rollout.id, channel_name: channel_token.channel_name
          )

          expect { service.execute }.not_to raise_error
        end
      end

      context 'when the push fails with an error retries cannot fix' do
        before do
          allow(kas_client).to receive(:send_to_workflow_channel).and_raise(GRPC::Unauthenticated.new('bad secret'))
        end

        it 'tracks the exception instead of raising' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            instance_of(GRPC::Unauthenticated), rollout_id: rollout.id, channel_name: channel_token.channel_name
          )

          expect { service.execute }.not_to raise_error
        end
      end

      context 'when the push fails with a transient gRPC error' do
        before do
          allow(kas_client).to receive(:send_to_workflow_channel).and_raise(GRPC::Unavailable.new('kas down'))
        end

        it 'raises so Sidekiq retries the job' do
          expect { service.execute }.to raise_error(GRPC::Unavailable)
        end
      end

      context 'when the push times out' do
        before do
          allow(kas_client).to receive(:send_to_workflow_channel).and_raise(GRPC::DeadlineExceeded.new('kas slow'))
        end

        it 'raises so Sidekiq retries the job, rather than dropping the decision' do
          expect { service.execute }.to raise_error(GRPC::DeadlineExceeded)
        end
      end
    end
  end
end
