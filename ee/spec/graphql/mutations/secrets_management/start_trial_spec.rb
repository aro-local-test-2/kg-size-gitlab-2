# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::SecretsManagement::StartTrial, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }

  subject(:mutation) { described_class.new(context: query_context, object: nil, field: nil) }

  before_all do
    root_group.add_owner(current_user)
    subgroup.add_owner(current_user)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(native_secrets_management: true)
  end

  describe '#resolve' do
    let(:success_response) do
      ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(success: true)
    end

    def resolve(group_path: root_group.full_path)
      mutation.resolve(group_path: group_path)
    end

    context 'when CDot starts the trial successfully', :saas do
      before do
        allow(client).to receive(:start_secrets_manager_trial)
          .with(namespace_id: root_group.id).and_return(success_response)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial))
      end

      it 'returns the post-trial entitlement with no errors', :aggregate_failures do
        result = resolve

        expect(result[:errors]).to be_empty
        expect(result[:entitlement]).to be_a(::Types::SecretsManagement::EntitlementType::Adapter)
        expect(result[:entitlement].state).to eq(:trial)
      end

      it 'tracks the secrets_manager_trial_started event' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_trial_started')
          .with(namespace: root_group, user: current_user, category: described_class.name)
          .and not_trigger_internal_events('secrets_manager_trial_start_failed')
      end

      it 'expires the cached CDot answers before reading the post-trial state' do
        expect(client).to receive(:expire_secrets_manager_cache)
          .with(namespace_id: root_group.id)
          .ordered
        expect(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial))
          .ordered

        resolve
      end

      # Without this the slot outlives the trial start, and a transport failure
      # on the lookup above replays the pre-trial answer for up to 24h.
      it 'drops the resolver caches, including the last-known-good slot' do
        expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache)
          .with(root_group)

        resolve
      end

      context 'when the post-trial entitlement lookup raises' do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(root_group, user: current_user)
            .and_raise(ActiveRecord::StatementInvalid, 'connection lost')
        end

        # CDot has already started the trial, so the mutation must still succeed.
        it 'reports the failure and returns a null entitlement with no errors', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(ActiveRecord::StatementInvalid),
            hash_including(gl_namespace_id: root_group.id)
          )

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to be_empty
        end
      end
    end

    context 'when CDot rejects the request', :saas do
      where(:error_code, :expected_message) do
        [
          [:trial_already_active, 'A Secrets Manager trial is already active for this group.'],
          [:not_found, 'This group is not recognized by the subscription service.'],
          [:ineligible, 'This group is not eligible to start a Secrets Manager trial.']
        ]
      end

      with_them do
        before do
          allow(client).to receive(:start_secrets_manager_trial).and_return(
            ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(
              success: false, error_code: error_code
            )
          )
        end

        it 'returns the mapped error and a nil entitlement', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(expected_message)
        end

        it 'tracks the trial start failure with the error code as label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_trial_start_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: error_code.to_s }
            )
            .and not_trigger_internal_events('secrets_manager_trial_started')
        end
      end

      context 'when ineligible with a CDot-supplied message' do
        before do
          allow(client).to receive(:start_secrets_manager_trial).and_return(
            ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(
              success: false, error_code: :ineligible, error_message: 'Namespace already used its trial'
            )
          )
        end

        it 'surfaces the CDot message' do
          expect(resolve[:errors]).to contain_exactly('Namespace already used its trial')
        end

        it 'tracks the trial start failure with the ineligible label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_trial_start_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'ineligible' }
            )
            .and not_trigger_internal_events('secrets_manager_trial_started')
        end
      end
    end

    context 'when the subscription service is unreachable', :saas do
      before do
        allow(client).to receive(:start_secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
      end

      it 'leaves the cache alone, since no trial was started' do
        expect(client).not_to receive(:expire_secrets_manager_cache)

        resolve
      end

      it 'tracks the trial start failure as unavailable' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_trial_start_failed')
          .with(
            namespace: root_group,
            user: current_user,
            category: described_class.name,
            additional_properties: { label: 'unavailable' }
          )
          .and not_trigger_internal_events('secrets_manager_trial_started')
      end

      it 'reports the failure to Sentry' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error),
          hash_including(gl_namespace_id: root_group.id)
        )

        resolve
      end
    end

    # NamespaceEnrollment.enrollment_allowed? is false for a non-root group, so
    # GroupPolicy prevents :start_secrets_manager_trial at authorization.
    context 'when the group is not a top-level group', :saas do
      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve(group_path: subgroup.full_path) }
          .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the feature flag is disabled', :saas do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the license does not include Secrets Manager', :saas do
      before do
        stub_licensed_features(native_secrets_management: false)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    # The trial flow enrolls the namespace first, so the trial shares the
    # enrollment gate and its rollout flag.
    context 'when the namespace enrollment feature flag is disabled', :saas do
      before do
        stub_feature_flags(secrets_manager_namespace_enrollment: false)
      end

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the user is a maintainer, not an owner', :saas do
      let_it_be(:maintainer) { create(:user, maintainer_of: root_group) }

      let(:current_user) { maintainer }

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    # The trial belongs to the instance on self-managed, so a group Owner must
    # not be able to start it; SecretsManagerInstanceStartTrial is the entry point.
    context 'on a self-managed install' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end
  end
end
