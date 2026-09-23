# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying Group.secretsManagerEntitlement', :saas, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let(:current_user) { owner }
  let(:target_group) { root_group }
  let(:cdot_timeout) { ::SecretsManagement::Entitlement::DEFAULT_HTTP_TIMEOUT_SECONDS }
  let(:query) do
    graphql_query_for(
      'group',
      { 'fullPath' => target_group.full_path },
      <<~FIELDS
        id
        secretsManagerEntitlement {
          state
          blockedReason
          trialStartedAt
          trialExpiresAt
          creditsRemaining
          creditsTotal
          onDemandEnabled
          betaProgramEnded
          betaWindowEligible
          offlineLicense
        }
      FIELDS
    )
  end

  let(:entitlement_response) { graphql_data_at(:group, :secrets_manager_entitlement) }

  before_all do
    root_group.add_owner(owner)
    root_group.add_maintainer(maintainer)
    subgroup.add_owner(owner)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(native_secrets_management: true)
    allow(::SecretsManagement::Availability).to receive(:enabled_for_group?).and_return(true)
  end

  shared_context 'with an online cloud license' do
    before do
      allow(::License).to receive(:current).and_return(
        instance_double(License, online_cloud_license?: true, feature_available?: false, plan: nil)
      )
    end
  end

  context 'when the FF is enabled and CDot returns an active trial' do
    include_context 'with an online cloud license'

    before do
      allow(::Gitlab::SubscriptionPortal::Client)
        .to receive(:secrets_manager_trial)
        .with(namespace_id: root_group.id, timeout: cdot_timeout)
        .and_return(
          ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial,
            trial_started_at: Time.zone.parse('2026-06-01T00:00:00Z'),
            trial_expires_at: Time.zone.parse('2026-07-01T00:00:00Z'),
            credits_remaining: 749.5,
            credits_total: 1000,
            on_demand_enabled: true
          )
        )
      allow(::Gitlab::SubscriptionPortal::Client)
        .to receive(:secrets_manager_consumer_resolve)
        .with(namespace_id: root_group.id, user_id: current_user.id, timeout: cdot_timeout)
        .and_return(
          ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
        )
    end

    it 'returns the mapped entitlement', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to include(
        'state' => 'TRIAL',
        'blockedReason' => nil,
        'trialStartedAt' => '2026-06-01T00:00:00Z',
        'trialExpiresAt' => '2026-07-01T00:00:00Z',
        'creditsRemaining' => 749.5,
        'creditsTotal' => 1000,
        'onDemandEnabled' => true,
        'betaWindowEligible' => false,
        'offlineLicense' => nil
      )
    end

    # `read_group` authorizes traversing the parent `Group` type,
    # `read_secrets_manager` the `SecretsManagerEntitlement` type
    it_behaves_like 'authorizing granular token permissions for GraphQL',
      %i[read_group read_secrets_manager] do
      let(:user) { owner }
      let(:boundary_object) { root_group }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  context 'when CDot reports an active trial blocked on credits' do
    include_context 'with an online cloud license'

    before do
      allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
        secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
          state: :trial,
          credits_remaining: 0,
          credits_total: 1000
        ),
        secrets_manager_consumer_resolve: ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
          blocked: true,
          blocked_reason: :credits_exhausted
        )
      )
    end

    it 'maps to BLOCKED + CREDITS_EXHAUSTED', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to include(
        'state' => 'BLOCKED',
        'blockedReason' => 'CREDITS_EXHAUSTED'
      )
    end
  end

  context 'when the FF is disabled' do
    before do
      stub_feature_flags(secrets_manager_paid_experience: false)
    end

    it 'returns null without calling CDot', :aggregate_failures do
      expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_trial)
      expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_consumer_resolve)

      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to be_nil
    end
  end

  context 'when CDot raises an error' do
    include_context 'with an online cloud license'

    before do
      allow(::Gitlab::SubscriptionPortal::Client)
        .to receive(:secrets_manager_trial)
        .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'CDot down')
      allow(::Gitlab::SubscriptionPortal::Client)
        .to receive(:secrets_manager_consumer_resolve)
        .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))
    end

    it 'fails closed and returns INELIGIBLE rather than a GraphQL error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to include('state' => 'INELIGIBLE')
    end
  end

  context 'when queried on a subgroup' do
    include_context 'with an online cloud license'
    let(:target_group) { subgroup }

    # Authorizing `read_secrets_manager` on a subgroup resolves the top-level
    # group's entitlement (subgroups are hidden while the state is
    # `trial_eligible`), so CDot is called during authorization. The field
    # itself stays null for non-root groups regardless of state: denied by
    # policy when `trial_eligible`, nulled by the resolver's root check
    # otherwise.
    %i[trial_eligible trial].each do |state|
      context "when the entitlement state is #{state}" do
        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: state),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
          )
        end

        it 'returns null', :aggregate_failures do
          post_graphql(query, current_user: current_user)
          expect_graphql_errors_to_be_empty
          expect(entitlement_response).to be_nil
        end
      end
    end
  end

  context 'when the current user lacks :read_secrets_manager' do
    let(:current_user) { non_member }

    it 'returns null (no authorization error surfaced) without calling CDot', :aggregate_failures do
      expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_trial)
      expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_consumer_resolve)

      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to be_nil
    end
  end

  context 'when availability is denied, for example after an explicit opt-out' do
    include_context 'with an online cloud license'

    before do
      allow(::SecretsManagement::Availability).to receive(:enabled_for_group?).and_return(false)
      allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
        secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial),
        secrets_manager_consumer_resolve:
          ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
      )
    end

    # Regression test: an opted-out group revokes :read_secrets_manager, but
    # owners must still read the entitlement or group settings cannot offer
    # the toggle to re-enroll.
    it 'still returns the entitlement to a user who can manage enrollment', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to include('state' => 'TRIAL')
    end

    context 'when the user cannot manage enrollment' do
      let(:current_user) { maintainer }

      it 'returns null', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(entitlement_response).to be_nil
      end
    end
  end

  context 'on a self-managed online cloud install' do
    let(:instance_uuid) { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }

    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      allow(::Gitlab).to receive(:com?).and_return(false)
      allow(::License).to receive(:current).and_return(
        instance_double(License, online_cloud_license?: true, trial?: false, feature_available?: false, plan: nil)
      )
      allow(::Gitlab::CurrentSettings).to receive(:uuid).and_return(instance_uuid)
    end

    it 'resolves the entitlement via instance_id (not namespace_id)', :aggregate_failures do
      expect(::Gitlab::SubscriptionPortal::Client)
        .to receive(:secrets_manager_trial).with(instance_id: instance_uuid, timeout: cdot_timeout)
        .and_return(
          ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial,
            credits_remaining: 750,
            credits_total: 1000,
            on_demand_enabled: true
          )
        )
      expect(::Gitlab::SubscriptionPortal::Client)
        .to receive(:secrets_manager_consumer_resolve)
        .with(instance_id: instance_uuid, user_id: current_user.id, timeout: cdot_timeout)
        .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))

      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(entitlement_response).to include(
        'state' => 'TRIAL',
        'creditsRemaining' => 750,
        'creditsTotal' => 1000,
        'onDemandEnabled' => true,
        'offlineLicense' => false
      )
    end

    # Self-managed records the beta cohort on the instance settings and exposes
    # it on the same field the frontend already reads on SaaS.
    context 'when the instance joined the free beta' do
      before do
        stub_feature_flags(end_secrets_manager_beta_program: false)
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: true
        )
        allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
          secrets_manager_trial:
            ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible),
          secrets_manager_consumer_resolve:
            ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
        )
      end

      it 'exposes betaWindowEligible', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_be_empty
        expect(entitlement_response).to include(
          'state' => 'TRIAL_ELIGIBLE',
          'betaWindowEligible' => true,
          'betaProgramEnded' => false
        )
      end
    end
  end
end
