# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Subscriptions::Cd::EnvironmentServiceUpdated, feature_category: :continuous_delivery do
  include GraphqlHelpers
  include ::Graphql::Subscriptions::Cd::EnvironmentServiceUpdated::Helper

  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:service) { create(:cd_service, application: application) }
  let_it_be(:environment) { create(:cd_environment, organization: organization) }
  let_it_be(:rollout_environment) { create(:cd_rollout_environment, environment: environment) }
  let_it_be(:deployment) { create(:cd_deployment, service: service, rollout_environment: rollout_environment) }

  let(:current_user) { nil }
  let(:subscribe) { cd_environment_service_updated_subscription(environment, current_user) }

  before do
    stub_const('GitlabSchema', Graphql::Subscriptions::ActionCable::MockGitlabSchema)
    Graphql::Subscriptions::ActionCable::MockActionCable.clear_mocks
  end

  subject(:response) do
    subscription_response do
      GraphqlTriggers.cd_environment_service_updated(deployment)
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
      graphql_dig_at(graphql_data(response[:result]), :cdEnvironmentServiceUpdated)
    end

    it 'receives the updated service' do
      expect(subscription_data).to include(
        'id' => service.to_global_id.to_s,
        'name' => service.name
      )
    end

    context 'when update is for a different environment id' do
      let_it_be(:other_environment) { create(:cd_environment, organization: organization) }
      let_it_be(:other_rollout_environment) { create(:cd_rollout_environment, environment: other_environment) }
      let_it_be(:other_deployment) do
        create(:cd_deployment, service: service, rollout_environment: other_rollout_environment)
      end

      subject(:response) do
        subscription_response do
          GraphqlTriggers.cd_environment_service_updated(other_deployment)
        end
      end

      it 'does not receive any data' do
        expect(response).to be_nil
      end
    end
  end
end
