# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Subscriptions::Cd::VersionSetUpdated, feature_category: :continuous_delivery do
  include GraphqlHelpers
  include ::Graphql::Subscriptions::Cd::VersionSetUpdated::Helper

  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }

  let(:current_user) { nil }
  let(:subscribe) { cd_version_set_updated_subscription(application, current_user) }

  before do
    stub_const('GitlabSchema', Graphql::Subscriptions::ActionCable::MockGitlabSchema)
    Graphql::Subscriptions::ActionCable::MockActionCable.clear_mocks
  end

  subject(:response) do
    subscription_response do
      GraphqlTriggers.cd_version_set_updated(version_set)
    end
  end

  context 'when unauthorized' do
    it 'does not receive any data' do
      expect(response).to be_nil
    end
  end

  context 'when authorized' do
    let_it_be(:authorized_user) { create(:organization_user, :owner, organization: organization).user }
    let(:current_user) { authorized_user }

    let(:subscription_data) do
      graphql_dig_at(graphql_data(response[:result]), :cdVersionSetUpdated)
    end

    it 'receives the updated version set' do
      expect(subscription_data).to include(
        'id' => version_set.to_global_id.to_s,
        'name' => version_set.name
      )
    end

    context 'with a rollout in progress' do
      before do
        create(:cd_rollout, version_set: version_set, state: :in_progress, workflow_ref: 'wk:1/abc')
      end

      it 'delivers the derived deploying status' do
        expect(subscription_data).to include('status' => 'DEPLOYING')
      end
    end

    context 'when update is for a different application' do
      let_it_be(:other_application) { create(:cd_application, organization: organization) }
      let_it_be(:other_version_set) { create(:cd_version_set, application: other_application) }

      subject(:response) do
        subscription_response do
          GraphqlTriggers.cd_version_set_updated(other_version_set)
        end
      end

      it 'does not receive any data' do
        expect(response).to be_nil
      end
    end
  end
end
