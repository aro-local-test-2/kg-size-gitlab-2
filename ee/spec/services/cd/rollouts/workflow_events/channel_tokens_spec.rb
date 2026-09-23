# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::WorkflowEvents::ChannelTokens, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }

  let(:rollout) do
    create(:cd_rollout, application: application, version_set: version_set, state: :in_progress,
      workflow_ref: 'wf-1')
  end

  subject(:workflow_event) { described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(params)) }

  describe '#execute' do
    context 'without channel_tokens' do
      let(:params) { { type: 'com.gitlab.cd.step_started', data: {} } }

      it 'does not persist anything' do
        expect { workflow_event.execute }.not_to change { rollout.rollout_channel_tokens.count }
      end
    end

    context 'with channel_tokens' do
      let(:params) do
        { type: 'com.gitlab.cd.step_started', data: {},
          channel_tokens: [{ channel_name: 'approval', token: 'a-token' }] }
      end

      it 'persists a channel token keyed to the rollout' do
        expect { workflow_event.execute }.to change { rollout.rollout_channel_tokens.count }.by(1)

        expect(rollout.rollout_channel_tokens.last).to have_attributes(channel_name: 'approval', token: 'a-token')
      end

      context 'when re-run for the same channel_name' do
        it 'overwrites the existing token rather than conflicting' do
          workflow_event.execute

          new_params = { type: 'com.gitlab.cd.step_started', data: {},
                         channel_tokens: [{ channel_name: 'approval', token: 'a-new-token' }] }
          new_event = described_class.new(rollout, Cd::Rollouts::WorkflowEvent.new(new_params))

          expect { new_event.execute }.not_to change { rollout.rollout_channel_tokens.count }
          expect(rollout.rollout_channel_tokens.last.token).to eq('a-new-token')
        end
      end

      context 'when the event names a step this rollout has' do
        let!(:step) { create(:cd_rollout_step, rollout: rollout, path: '0.1') }

        let(:params) do
          { type: 'com.gitlab.cd.step_started', data: { position: [0, 1] },
            channel_tokens: [{ channel_name: 'approval', token: 'a-token' }] }
        end

        it 'links the persisted token to that step' do
          workflow_event.execute

          expect(rollout.rollout_channel_tokens.last.rollout_step).to eq(step)
        end
      end

      context 'when the event names no step' do
        it 'persists the token with no rollout_step' do
          workflow_event.execute

          expect(rollout.rollout_channel_tokens.last.rollout_step).to be_nil
        end
      end

      context 'when the event names a step this rollout does not have' do
        let(:params) do
          { type: 'com.gitlab.cd.step_started', data: { position: [9, 9] },
            channel_tokens: [{ channel_name: 'approval', token: 'a-token' }] }
        end

        it 'persists the token with no rollout_step' do
          workflow_event.execute

          expect(rollout.rollout_channel_tokens.last.rollout_step).to be_nil
        end
      end
    end
  end
end
