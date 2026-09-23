# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Subscriptions::Cd::RolloutGateUpdated, feature_category: :continuous_delivery do
  include GraphqlHelpers
  include ::Graphql::Subscriptions::Cd::RolloutGateUpdated::Helper

  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }
  let_it_be(:rollout) { create(:cd_rollout, version_set: version_set) }

  let(:current_user) { nil }
  let(:subscribe) { cd_rollout_gate_updated_subscription(rollout, current_user) }

  before do
    stub_feature_flags(ai_native_deploy: true)
    stub_const('GitlabSchema', Graphql::Subscriptions::ActionCable::MockGitlabSchema)
    Graphql::Subscriptions::ActionCable::MockActionCable.clear_mocks
  end

  subject(:response) do
    subscription_response do
      GraphqlTriggers.cd_rollout_gate_updated(rollout)
    end
  end

  context 'when unauthorized' do
    before do
      create(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
    end

    it 'does not receive any data' do
      expect(response).to be_nil
    end
  end

  context 'when authorized' do
    let_it_be(:authorized_user) { create(:organization_user, :owner, organization: organization).user }
    let(:current_user) { authorized_user }

    let(:subscription_data) do
      graphql_dig_at(graphql_data(response[:result]), :cdRolloutGateUpdated)
    end

    context 'with an open gate' do
      before do
        create(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
      end

      it 'delivers the rollout with the gate pending' do
        expect(subscription_data).to include('id' => rollout.to_global_id.to_s, 'awaitingApproval' => true)
        expect(subscription_data['gates']).to contain_exactly('state' => 'PENDING')
      end
    end

    context 'with a resolved gate' do
      before do
        create(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
        create(:cd_rollout_transition, rollout: rollout, event: 'approve')
      end

      it 'delivers the rollout with the gate resolved' do
        expect(subscription_data).to include('id' => rollout.to_global_id.to_s, 'awaitingApproval' => false)
        expect(subscription_data['gates']).to contain_exactly('state' => 'APPROVED')
      end
    end

    context 'when update is for a different rollout' do
      let_it_be(:other_application) { create(:cd_application, organization: organization) }
      let_it_be(:other_version_set) { create(:cd_version_set, application: other_application) }
      let_it_be(:other_rollout) { create(:cd_rollout, version_set: other_version_set) }

      subject(:response) do
        subscription_response do
          GraphqlTriggers.cd_rollout_gate_updated(other_rollout)
        end
      end

      it 'does not receive any data' do
        expect(response).to be_nil
      end
    end
  end
end
