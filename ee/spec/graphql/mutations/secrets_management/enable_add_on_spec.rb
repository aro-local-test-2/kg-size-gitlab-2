# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::SecretsManagement::EnableAddOn, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }

  let(:eligible_entitlement) do
    ::SecretsManagement::Entitlement.new(state: :trial_eligible, on_demand_enabled: true)
  end

  let(:paid_entitlement) do
    ::SecretsManagement::Entitlement.new(state: :paid, on_demand_enabled: true)
  end

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
    def resolve(group_path: root_group.full_path)
      mutation.resolve(group_path: group_path)
    end

    def enrollment
      ::SecretsManagement::NamespaceEnrollment.find_by_namespace_id(root_group.id)
    end

    context 'when the group is billable (trial_eligible with on-demand accepted)', :saas do
      before do
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(eligible_entitlement, paid_entitlement)
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(paid_entitlement)
        allow(client).to receive(:expire_secrets_manager_cache)
        allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success)
        end
      end

      it 'records the add-on intent and returns the paid entitlement', :aggregate_failures do
        result = resolve

        expect(result[:errors]).to be_empty
        expect(result[:entitlement]).to be_a(::Types::SecretsManagement::EntitlementType::Adapter)
        expect(result[:entitlement].state).to eq(:paid)
        expect(enrollment.add_on_requested_at).to be_present
        expect(enrollment).to be_enabled
      end

      it 'provisions the secrets manager' do
        expect_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
          expect(service).to receive(:execute).and_return(ServiceResponse.success)
        end

        resolve
      end

      it 'tracks the secrets_manager_add_on_enabled event' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_add_on_enabled')
          .with(namespace: root_group, user: current_user, category: described_class.name)
          .and not_trigger_internal_events('secrets_manager_add_on_enable_failed')
      end

      it 'audits the paid conversion' do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

        resolve

        expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
          hash_including(name: 'secrets_manager_add_on_enable')
        )
      end

      it 'expires the cached CDot answers before validating billability' do
        expect(client).to receive(:expire_secrets_manager_cache)
          .with(namespace_id: root_group.id)
          .ordered
        expect(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(eligible_entitlement, paid_entitlement)
          .ordered

        resolve
      end

      context 'when the intent was already recorded (re-click after partial failure)' do
        let_it_be(:existing_requested_at) { 2.days.ago.change(usec: 0) }

        before do
          create(
            :secrets_manager_namespace_enrollment,
            namespace: root_group, add_on_requested_at: existing_requested_at
          )
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(root_group, user: current_user)
            .and_return(paid_entitlement)
        end

        it 'keeps the original intent timestamp and still provisions', :aggregate_failures do
          result = resolve

          expect(result[:errors]).to be_empty
          expect(enrollment.add_on_requested_at).to eq(existing_requested_at)
        end

        it 'does not re-audit a conversion that already happened' do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

          resolve

          expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(
            hash_including(name: 'secrets_manager_add_on_enable')
          )
        end

        it 'does not count the conversion again' do
          expect { resolve }
            .to not_trigger_internal_events('secrets_manager_add_on_enabled')
            .and not_trigger_internal_events('secrets_manager_add_on_enable_failed')
        end
      end

      context 'when the group had previously opted out' do
        before do
          create(:secrets_manager_namespace_enrollment, :disabled, namespace: root_group)
        end

        it 're-enables the enrollment and records the intent', :aggregate_failures do
          result = resolve

          expect(result[:errors]).to be_empty
          expect(enrollment).to be_enabled
          expect(enrollment.add_on_requested_at).to be_present
        end
      end

      context 'when provisioning reports the manager already exists' do
        before do
          allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(
                message: 'Secrets manager already initialized for the group.',
                reason: :already_initialized
              )
            )
          end
        end

        it 'treats it as success' do
          expect(resolve[:errors]).to be_empty
        end
      end

      context 'when provisioning fails' do
        before do
          allow_next_instance_of(::SecretsManagement::GroupSecretsManagers::InitializeService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'provisioning boom'))
          end
        end

        it 'surfaces the error but keeps the recorded intent so a re-click can retry', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly('provisioning boom')
          expect(enrollment.add_on_requested_at).to be_present
        end

        it 'tracks the failure with the provisioning_failed label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_add_on_enable_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'provisioning_failed' }
            )
        end

        # The group is billable once the intent resolves to paid, so the
        # conversion must be counted even though provisioning did not finish.
        it 'still counts the conversion' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_add_on_enabled')
            .with(namespace: root_group, user: current_user, category: described_class.name)
        end
      end

      context 'when the post-intent entitlement does not resolve to paid' do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(root_group, user: current_user)
            .and_return(eligible_entitlement, eligible_entitlement)
        end

        it 'removes the enrollment created for the intent and returns an error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
          expect(enrollment).to be_nil
        end

        it 'does not audit a conversion for the reverted intent' do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

          resolve

          expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(
            hash_including(name: 'secrets_manager_add_on_enable')
          )
        end

        context 'when the group was already enrolled (trial-chain or beta)' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group)
          end

          it 'keeps the enrollment but clears the intent', :aggregate_failures do
            result = resolve

            expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
            expect(enrollment).to be_enabled
            expect(enrollment.add_on_requested_at).to be_nil
          end
        end

        context 'when the group had opted out' do
          before do
            create(:secrets_manager_namespace_enrollment, :disabled, namespace: root_group)
          end

          it 'restores the opt-out that enroll re-enabled', :aggregate_failures do
            result = resolve

            expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
            expect(enrollment).not_to be_enabled
            expect(enrollment.add_on_requested_at).to be_nil
          end
        end

        it 'tracks the failure with the not_billable label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_add_on_enable_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'not_billable' }
            )
            .and not_trigger_internal_events('secrets_manager_add_on_enabled')
        end
      end

      context 'when enrollment is not allowed' do
        before do
          allow_next_instance_of(::SecretsManagement::NamespaceEnrollmentService) do |service|
            allow(service).to receive(:enroll).and_return(
              ServiceResponse.error(message: 'Namespace enrollment is not allowed.', reason: :forbidden)
            )
          end
        end

        it 'surfaces the enrollment error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly('Namespace enrollment is not allowed.')
        end

        it 'tracks the failure with the enrollment_failed label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_add_on_enable_failed')
            .with(
              namespace: root_group,
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'enrollment_failed' }
            )
            .and not_trigger_internal_events('secrets_manager_add_on_enabled')
        end
      end
    end

    context 'when on-demand billing is not accepted', :saas do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial_eligible, on_demand_enabled: false))
      end

      it 'rejects without recording intent', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::ON_DEMAND_DISABLED_ERROR)
        expect(enrollment).to be_nil
      end

      it 'tracks the failure with the on_demand_disabled label' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_add_on_enable_failed')
          .with(
            namespace: root_group,
            user: current_user,
            category: described_class.name,
            additional_properties: { label: 'on_demand_disabled' }
          )
          .and not_trigger_internal_events('secrets_manager_add_on_enabled')
      end
    end

    context 'when the group is not in an eligible state', :saas do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(root_group, user: current_user)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial))
      end

      it 'rejects as ineligible without recording intent', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
        expect(enrollment).to be_nil
      end
    end

    context 'when the subscription service is unreachable', :saas do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
      end

      it 'reports the failure to Sentry' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error),
          hash_including(gl_namespace_id: root_group.id)
        )

        resolve
      end
    end

    # NamespaceEnrollment.enrollment_allowed? is false for a non-root group, so
    # GroupPolicy prevents :enable_secrets_manager_add_on at authorization.
    context 'when the group is not a top-level group', :saas do
      it 'raises a resource not available error' do
        expect { resolve(group_path: subgroup.full_path) }
          .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the feature flag is disabled', :saas do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    # The authorize ability is :enable_secrets_manager_add_on, which GroupPolicy
    # gates on enrollment_allowed?, so the gate is enforced at the door, not inside the service.
    context 'when namespace enrollment is not allowed', :saas do
      before do
        stub_feature_flags(secrets_manager_namespace_enrollment: false)
      end

      it 'raises a resource not available error' do
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

    context 'on a self-managed install' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end
  end
end
