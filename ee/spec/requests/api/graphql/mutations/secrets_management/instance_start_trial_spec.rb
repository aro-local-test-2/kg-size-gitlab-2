# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Start the instance-wide Secrets Manager trial', feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:group_owner) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:instance_id) { ::Gitlab::CurrentSettings.uuid }
  let(:current_user) { admin }
  let(:mutation_name) { :secrets_manager_instance_start_trial }

  let(:mutation) { graphql_mutation(mutation_name, {}, 'entitlement { state creditsRemaining } errors') }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before_all do
    root_group.add_owner(group_owner)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_licensed_features(native_secrets_management: true)
    allow(::License).to receive(:current).and_return(
      instance_double(License, online_cloud_license?: true, feature_available?: true, plan: nil)
    )
  end

  shared_context 'with a trial-eligible instance and a successful CDot start' do
    before do
      allow(client).to receive(:expire_secrets_manager_cache)
      allow(client).to receive(:start_secrets_manager_trial)
        .with(instance_id: instance_id)
        .and_return(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(success: true))
      allow(::SecretsManagement::Entitlement).to receive(:for!)
        .with(nil, user: an_instance_of(User))
        .and_return(
          ::SecretsManagement::Entitlement.new(state: :trial_eligible),
          ::SecretsManagement::Entitlement.new(state: :trial, credits_remaining: 500)
        )
    end
  end

  context 'when the current user is an admin', :enable_admin_mode do
    context 'when CDot starts the trial successfully' do
      include_context 'with a trial-eligible instance and a successful CDot start'

      it 'starts the trial by instance id and returns the post-trial entitlement', :aggregate_failures do
        post_mutation

        expect(client).to have_received(:start_secrets_manager_trial).with(instance_id: instance_id)
        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['entitlement']).to eq('state' => 'TRIAL', 'creditsRemaining' => 500)
      end

      it 'enrolls the instance' do
        expect { post_mutation }
          .to change { ::Gitlab::CurrentSettings.secrets_manager_instance_enrolled }.from(false).to(true)
      end

      it 'tracks the secrets_manager_instance_trial_started event' do
        expect { post_mutation }
          .to trigger_internal_events('secrets_manager_instance_trial_started')
          .with(user: admin, category: 'Mutations::SecretsManagement::InstanceStartTrial')
          .and not_trigger_internal_events('secrets_manager_instance_trial_start_failed')
      end

      # Both scopes: the mutation's own, plus the one the returned EntitlementType requires.
      it_behaves_like 'authorizing granular token permissions for GraphQL',
        %i[start_secrets_manager_trial read_secrets_manager] do
        let(:user) { admin }
        let(:boundary_object) { :instance }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }

        # One-short: the shared example only proves a token holding every permission passes.
        context 'when the token lacks the payload type permission' do
          let(:pat) do
            create(:granular_pat, user: user, boundary: boundary,
              permissions: ['start_secrets_manager_trial'])
          end

          let(:message) { 'Secrets Manager: Read' }

          it_behaves_like 'denying access'
        end
      end
    end

    context 'when a trial is already active (re-click)' do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: admin)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial))
      end

      it 'returns the already-active error without calling CDot', :aggregate_failures do
        expect(client).not_to receive(:start_secrets_manager_trial)

        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          'A Secrets Manager trial is already active for this instance.'
        )
        expect(mutation_response['entitlement']).to be_nil
      end
    end

    context 'when CDot is unreachable' do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: admin)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial_eligible))
        allow(client).to receive(:start_secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error' do
        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceStartTrial::UNAVAILABLE_ERROR
        )
      end
    end

    context 'on an offline (air-gapped) install' do
      before do
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: false, feature_available?: true, plan: nil)
        )
      end

      it 'rejects with the offline error and never calls CDot', :aggregate_failures do
        expect(client).not_to receive(:start_secrets_manager_trial)

        post_mutation

        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceStartTrial::OFFLINE_ERROR
        )
      end
    end

    context 'when the license does not include Secrets Manager' do
      before do
        stub_licensed_features(native_secrets_management: false)
      end

      it 'returns a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'when the paid-experience feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'returns a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end

    context 'when on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns a resource not available error (the instance trial is self-managed only)' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end
  end

  context 'when the current user is a top-level group Owner but not an admin' do
    let(:current_user) { group_owner }

    it 'returns a resource not available error and never calls CDot' do
      expect(client).not_to receive(:start_secrets_manager_trial)

      post_mutation

      expect_graphql_errors_to_include("you don't have permission")
    end
  end
end
