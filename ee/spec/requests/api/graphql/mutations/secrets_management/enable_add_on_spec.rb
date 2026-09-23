# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Enable the Secrets Manager add-on', feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:current_user) { owner }
  let(:target_group) { root_group }
  let(:mutation_name) { :secrets_manager_enable_add_on }

  let(:mutation) { graphql_mutation(mutation_name, group_path: target_group.full_path) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before_all do
    root_group.add_owner(owner)
    root_group.add_maintainer(maintainer)
    subgroup.add_owner(owner)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(native_secrets_management: true)
  end

  context 'when the current user is the group owner' do
    # Stubs only the CDot HTTP client; enrollment, the entitlement resolver
    # (including the intent -> :paid mapping), and provisioning run for real.
    context 'when the group is billable (trial_eligible, on-demand accepted)', :saas do
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

      it 'records intent, resolves to paid, and provisions the secrets manager', :aggregate_failures do
        post_mutation

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['entitlement']).to include('state' => 'PAID')

        enrollment = ::SecretsManagement::NamespaceEnrollment.find_by_namespace_id(root_group.id)
        expect(enrollment.add_on_requested_at).to be_present
        expect(enrollment.beta).to be false

        expect(root_group.reload.secrets_manager).to be_present
      end

      it 'tracks the secrets_manager_add_on_enabled event' do
        expect { post_mutation }
          .to trigger_internal_events('secrets_manager_add_on_enabled')
          .with(namespace: root_group, user: owner, category: 'Mutations::SecretsManagement::EnableAddOn')
          .and not_trigger_internal_events('secrets_manager_add_on_enable_failed')
      end

      # Both scopes: the mutation's own, plus the one the returned EntitlementType requires.
      it_behaves_like 'authorizing granular token permissions for GraphQL',
        %i[enable_secrets_manager_add_on read_secrets_manager] do
        let(:user) { owner }
        let(:boundary_object) { root_group }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

        # One-short: the shared example only proves a token holding every permission passes.
        context 'when the token lacks the payload type permission' do
          let(:pat) do
            create(:granular_pat, user: user, boundary: boundary, permissions: ['enable_secrets_manager_add_on'])
          end

          let(:message) { 'Secrets Manager: Read' }

          it_behaves_like 'denying access'
        end
      end

      it_behaves_like 'a secrets manager mutation blocked on an inactive namespace' do
        let(:inactive_namespace) { root_group }
      end
    end

    context 'when on-demand billing is not accepted', :saas do
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

      it 'rejects without recording intent or provisioning', :aggregate_failures do
        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::EnableAddOn::ON_DEMAND_DISABLED_ERROR
        )
        expect(mutation_response['entitlement']).to be_nil
        expect(::SecretsManagement::NamespaceEnrollment.find_by_namespace_id(root_group.id)).to be_nil
        expect(root_group.reload.secrets_manager).to be_nil
      end
    end

    context 'when a trial is already active', :saas do
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
          Mutations::SecretsManagement::EnableAddOn::INELIGIBLE_ERROR
        )
      end
    end

    context 'when CDot is unreachable', :saas do
      before do
        allow(client).to receive(:secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error' do
        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::EnableAddOn::UNAVAILABLE_ERROR
        )
      end
    end

    # NamespaceEnrollment.enrollment_allowed? is false for a non-root group, so
    # GroupPolicy prevents :enable_secrets_manager_add_on at authorization, like NamespaceSecretsManagerEnroll.
    context 'when targeting a subgroup' do
      let(:target_group) { subgroup }

      it 'returns a resource not available error' do
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

    context 'on a self-managed install' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'returns a resource not available error' do
        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end
  end

  context 'when the current user is only a maintainer' do
    let(:current_user) { maintainer }

    it_behaves_like 'a mutation on an unauthorized resource'
  end

  context 'when the current user is not a member' do
    let(:current_user) { non_member }

    it_behaves_like 'a mutation on an unauthorized resource'
  end
end
