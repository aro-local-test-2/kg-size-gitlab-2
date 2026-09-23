# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Enable the Secrets Manager add-on for the instance', feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:current_user) { admin }
  let(:mutation_name) { :secrets_manager_instance_enable_add_on }
  let(:license) do
    instance_double(License, online_cloud_license?: true, trial?: false, feature_available?: false, plan: nil)
  end

  let(:mutation) { graphql_mutation(mutation_name, {}) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  def settings
    ::Gitlab::CurrentSettings.current_application_settings
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    allow(::License).to receive(:current).and_return(license)
    allow(::License).to receive(:feature_available?).and_call_original
    allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
  end

  context 'when the current user is an admin' do
    # Stubs only the CDot HTTP client; enrollment and the entitlement resolver
    # (including the intent -> :paid mapping) run for real.
    context 'when the instance is billable (trial_eligible, on-demand accepted)' do
      let(:trial_response) do
        ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
          state: :trial_eligible, on_demand_enabled: true
        )
      end

      let(:resolve_response) do
        ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
      end

      before do
        allow(client).to receive_messages(
          secrets_manager_trial: trial_response,
          secrets_manager_consumer_resolve: resolve_response
        )
      end

      it 'enrolls the instance, records intent and resolves to paid', :aggregate_failures do
        post_mutation

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['entitlement']).to include('state' => 'PAID')

        expect(settings.secrets_manager_instance_enrolled).to be true
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_present
      end

      it 'asks CDot about the instance, not a namespace' do
        post_mutation

        expect(client).to have_received(:secrets_manager_trial)
          .with(instance_id: ::Gitlab::CurrentSettings.uuid).at_least(:once)
      end

      # Policies and CI resolve the entitlement with the root group, not nil; the
      # paid state must be visible there too or nobody can create a secret after paying.
      it 'makes the paid state visible to group-scoped entitlement checks' do
        group = create(:group)

        post_mutation

        expect(::SecretsManagement::Entitlement.for(group, user: admin).state).to eq(:paid)
      end

      it 'tracks the secrets_manager_add_on_enabled event' do
        expect { post_mutation }
          .to trigger_internal_events('secrets_manager_add_on_enabled')
          .with(user: admin, category: 'Mutations::SecretsManagement::InstanceEnableAddOn')
          .and not_trigger_internal_events('secrets_manager_add_on_enable_failed')
      end

      context 'when the intent was already recorded (re-click)' do
        let(:existing_requested_at) { 2.days.ago.change(usec: 0) }

        before do
          ::Gitlab::CurrentSettings.update!(
            secrets_manager_instance_enrolled: true,
            secrets_manager_instance_add_on_requested_at: existing_requested_at
          )
        end

        it 'is idempotent', :aggregate_failures do
          expect { post_mutation }.not_to trigger_internal_events('secrets_manager_add_on_enabled')

          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['entitlement']).to include('state' => 'PAID')
          expect(settings.secrets_manager_instance_add_on_requested_at).to eq(existing_requested_at)
        end
      end

      # Both scopes: the mutation's own, plus the one the returned EntitlementType requires.
      it_behaves_like 'authorizing granular token permissions for GraphQL',
        %i[enable_secrets_manager_add_on read_secrets_manager] do
        let(:user) { admin }
        let(:boundary_object) { :instance }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      # The shared example only checks the top-level payload, which would pass
      # with a silently nulled entitlement; pin the nested type explicitly.
      context 'with a granular token holding both scopes' do
        let(:assignables) do
          %i[enable_secrets_manager_add_on read_secrets_manager].map do |permission|
            ::Authz::PermissionGroups::Assignable.for_permission(permission).first.name
          end.uniq
        end

        let(:pat) do
          create(:granular_pat, user: admin, boundary: ::Authz::Boundary.for(:instance), permissions: assignables)
        end

        it 'returns the entitlement in the payload', :aggregate_failures do
          post_graphql_mutation(mutation, token: { personal_access_token: pat })

          expect_graphql_errors_to_be_empty
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['entitlement']).to include('state' => 'PAID')
        end
      end

      # Without `read_secrets_manager` in the mutation's own scope, a token holding
      # only the enable permission would convert the instance and get a silent
      # null entitlement; it must be denied before any side effect instead.
      context 'with a granular token holding only the enable scope' do
        let(:assignables) do
          [::Authz::PermissionGroups::Assignable.for_permission(:enable_secrets_manager_add_on).first.name]
        end

        let(:pat) do
          create(:granular_pat, user: admin, boundary: ::Authz::Boundary.for(:instance), permissions: assignables)
        end

        it 'is denied without recording intent', :aggregate_failures do
          post_graphql_mutation(mutation, token: { personal_access_token: pat })

          expect_graphql_errors_to_include('Access denied')
          expect(settings.secrets_manager_instance_enrolled).to be false
          expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
        end
      end
    end

    context 'when on-demand billing is not accepted' do
      before do
        allow(client).to receive_messages(
          secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial_eligible, on_demand_enabled: false
          ),
          secrets_manager_consumer_resolve:
            ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
              blocked: true, blocked_reason: :on_demand_disabled
            )
        )
      end

      it 'rejects without recording intent or enrolling', :aggregate_failures do
        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceEnableAddOn::ON_DEMAND_DISABLED_ERROR
        )
        expect(mutation_response['entitlement']).to be_nil
        expect(settings.secrets_manager_instance_enrolled).to be false
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end
    end

    context 'when a trial is already active' do
      before do
        allow(client).to receive_messages(
          secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial, on_demand_enabled: true, credits_remaining: 100, credits_total: 500
          ),
          secrets_manager_consumer_resolve:
            ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
        )
      end

      it 'rejects as ineligible' do
        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceEnableAddOn::INELIGIBLE_ERROR
        )
      end
    end

    context 'when CDot is unreachable' do
      before do
        allow(client).to receive(:secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error' do
        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceEnableAddOn::UNAVAILABLE_ERROR
        )
      end
    end

    context 'on an offline environment or legacy license' do
      let(:license) do
        instance_double(License, online_cloud_license?: false, trial?: false, feature_available?: false, plan: nil)
      end

      it 'rejects with the offline error and never calls CDot', :aggregate_failures do
        expect(client).not_to receive(:secrets_manager_trial)

        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceEnableAddOn::OFFLINE_ERROR
        )
      end
    end

    # No license means the licensed feature is unavailable, so the policy denies.
    context 'on a self-managed install with no license' do
      let(:license) { nil }

      before do
        allow(::License).to receive(:feature_available?).and_call_original
      end

      it 'returns a resource not available error and never calls CDot' do
        expect(client).not_to receive(:secrets_manager_trial)

        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'returns a resource not available error' do
        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'when the licensed feature is not available' do
      before do
        allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(false)
      end

      it 'returns a resource not available error' do
        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns a resource not available error (the instance add-on is self-managed only)' do
        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end
  end

  context 'when the current user is not an admin' do
    let(:current_user) { user }

    it_behaves_like 'a mutation on an unauthorized resource'
  end
end
