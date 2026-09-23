# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying the instance-wide Secrets Manager entitlement', feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:group_owner) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }

  let(:current_user) { admin }
  let(:query) do
    graphql_query_for(:secrets_manager_instance_entitlement, {}, 'state creditsRemaining offlineLicense')
  end

  subject(:resolved_value) do
    post_graphql(query, current_user: current_user)
    graphql_data_at(:secrets_manager_instance_entitlement)
  end

  before_all do
    root_group.add_owner(group_owner)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_licensed_features(native_secrets_management: true)
  end

  context 'when the current user is an admin', :enable_admin_mode do
    before do
      allow(::SecretsManagement::Entitlement).to receive(:for)
        .with(nil, user: an_instance_of(User))
        .and_return(::SecretsManagement::Entitlement.new(state: :trial, credits_remaining: 250))
    end

    it 'returns the instance-wide entitlement' do
      expect(resolved_value).to include('state' => 'TRIAL', 'creditsRemaining' => 250)
    end

    context 'with an online cloud license' do
      before do
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: true, feature_available?: true, plan: nil)
        )
      end

      it 'reports the license as online' do
        expect(resolved_value).to include('offlineLicense' => false)
      end
    end

    context 'with an offline license' do
      before do
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: false, feature_available?: true, plan: nil)
        )
      end

      it 'reports the license as offline regardless of the entitlement state' do
        expect(resolved_value).to include('state' => 'TRIAL', 'offlineLicense' => true)
      end
    end

    # The resolver uses `Entitlement.for`, not `for!`: a CDot outage must fail
    # closed to INELIGIBLE instead of surfacing a GraphQL error.
    context 'when CustomersDot is unreachable' do
      before do
        allow(::SecretsManagement::Entitlement).to receive(:for).and_call_original
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: true, trial?: false, feature_available?: true, plan: nil)
        )
        allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'CDot down')
        allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_consumer_resolve)
          .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))
      end

      it 'fails closed and returns INELIGIBLE rather than a GraphQL error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:secrets_manager_instance_entitlement)).to include('state' => 'INELIGIBLE')
      end
    end

    it 'resolves the entitlement without a namespace' do
      resolved_value

      expect(::SecretsManagement::Entitlement).to have_received(:for).with(nil, user: admin)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_secrets_manager do
      let(:user) { admin }
      let(:boundary_object) { :instance }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end

    context 'when the license does not include Secrets Manager' do
      before do
        stub_licensed_features(native_secrets_management: false)
      end

      it 'returns a resource not available error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'when the paid-experience feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'returns a resource not available error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'when on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns a resource not available error (entitlement is per top-level group there)' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include("you don't have permission")
      end
    end
  end

  context 'when the current user is a top-level group Owner but not an admin' do
    let(:current_user) { group_owner }

    it 'returns a resource not available error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include("you don't have permission")
    end
  end
end
