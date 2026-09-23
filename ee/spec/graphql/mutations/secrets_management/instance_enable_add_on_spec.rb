# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::SecretsManagement::InstanceEnableAddOn, :enable_admin_mode,
  feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  let(:current_user) { admin }
  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:license) do
    instance_double(License, online_cloud_license?: true, trial?: false, feature_available?: false, plan: nil)
  end

  let(:eligible_entitlement) do
    ::SecretsManagement::Entitlement.new(state: :trial_eligible, on_demand_enabled: true)
  end

  let(:paid_entitlement) do
    ::SecretsManagement::Entitlement.new(state: :paid, on_demand_enabled: true)
  end

  subject(:mutation) { described_class.new(context: query_context, object: nil, field: nil) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    allow(::License).to receive(:current).and_return(license)
    allow(::License).to receive(:feature_available?).and_call_original
    allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
  end

  describe '#resolve' do
    def resolve
      mutation.resolve
    end

    def settings
      ::Gitlab::CurrentSettings.current_application_settings
    end

    context 'when the instance is billable (trial_eligible with on-demand accepted)' do
      before do
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_return(eligible_entitlement, paid_entitlement)
        allow(client).to receive(:expire_secrets_manager_cache)
      end

      it 'enrolls the instance, records the add-on intent and returns the paid entitlement', :aggregate_failures do
        result = resolve

        expect(result[:errors]).to be_empty
        expect(result[:entitlement]).to be_a(::Types::SecretsManagement::EntitlementType::Adapter)
        expect(result[:entitlement].state).to eq(:paid)
        expect(settings.secrets_manager_instance_enrolled).to be true
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_present
      end

      it 'tracks the secrets_manager_add_on_enabled event without a namespace' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_add_on_enabled')
          .with(user: current_user, category: described_class.name)
          .and not_trigger_internal_events('secrets_manager_add_on_enable_failed')
          .and increment_usage_metrics(
            'counts.count_total_secrets_manager_add_on_enabled_monthly',
            'counts.count_total_secrets_manager_add_on_enabled_weekly',
            'counts.count_total_secrets_manager_add_on_enabled'
          )
      end

      it 'audits the enrollment and the paid conversion at instance scope', :aggregate_failures do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

        resolve

        expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
          hash_including(name: 'secrets_manager_instance_enroll', scope: an_instance_of(::Gitlab::Audit::InstanceScope))
        )
        expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
          hash_including(name: 'secrets_manager_add_on_enable', scope: an_instance_of(::Gitlab::Audit::InstanceScope))
        )
      end

      it 'expires the cached CDot answers for the instance before validating billability' do
        expect(client).to receive(:expire_secrets_manager_cache)
          .with(instance_id: ::Gitlab::CurrentSettings.uuid)
          .ordered
        expect(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_return(eligible_entitlement, paid_entitlement)
          .ordered

        resolve
      end

      context 'when the instance was already enrolled (beta cohort)' do
        before do
          ::Gitlab::CurrentSettings.update!(secrets_manager_instance_enrolled: true)
        end

        it 'records the intent without re-enrolling', :aggregate_failures do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

          result = resolve

          expect(result[:errors]).to be_empty
          expect(settings.secrets_manager_instance_add_on_requested_at).to be_present
          expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(
            hash_including(name: 'secrets_manager_instance_enroll')
          )
        end
      end

      context 'when the intent was already recorded (re-click after partial failure)' do
        let(:existing_requested_at) { 2.days.ago.change(usec: 0) }

        before do
          ::Gitlab::CurrentSettings.update!(
            secrets_manager_instance_enrolled: true,
            secrets_manager_instance_add_on_requested_at: existing_requested_at
          )
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(nil, user: current_user)
            .and_return(paid_entitlement)
        end

        it 'keeps the original intent timestamp', :aggregate_failures do
          result = resolve

          expect(result[:errors]).to be_empty
          expect(settings.secrets_manager_instance_add_on_requested_at).to eq(existing_requested_at)
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

      context 'when the post-intent entitlement does not resolve to paid' do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(nil, user: current_user)
            .and_return(eligible_entitlement, eligible_entitlement)
        end

        it 'reverts the enrollment created for the intent and returns an error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
          expect(settings.secrets_manager_instance_enrolled).to be false
          expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
        end

        it 'audits the reverted enrollment but not a conversion', :aggregate_failures do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

          resolve

          expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
            hash_including(
              name: 'secrets_manager_instance_unenroll',
              message: 'Reverted Secrets Manager enrollment after failed add-on enable'
            )
          )
          expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(
            hash_including(name: 'secrets_manager_add_on_enable')
          )
        end

        it 'tracks the failure with the not_billable label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_add_on_enable_failed')
            .with(
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'not_billable' }
            )
            .and not_trigger_internal_events('secrets_manager_add_on_enabled')
            .and increment_usage_metrics(
              'counts.count_total_secrets_manager_add_on_enable_failed_monthly',
              'counts.count_total_secrets_manager_add_on_enable_failed_weekly',
              'counts.count_total_secrets_manager_add_on_enable_failed'
            )
        end

        context 'when the instance was already enrolled' do
          before do
            ::Gitlab::CurrentSettings.update!(secrets_manager_instance_enrolled: true)
          end

          it 'keeps the enrollment but clears the intent', :aggregate_failures do
            allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

            result = resolve

            expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
            expect(settings.secrets_manager_instance_enrolled).to be true
            expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
            expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(
              hash_including(name: 'secrets_manager_instance_unenroll')
            )
          end
        end
      end

      context 'when recording the intent fails' do
        before do
          allow_next_instance_of(::SecretsManagement::InstanceEnrollmentService) do |service|
            allow(service).to receive(:enroll_with_add_on_intent).and_return(
              ServiceResponse.error(message: 'Instance enrollment is only available on self-managed instances.')
            )
          end
        end

        it 'surfaces the enrollment error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly('Instance enrollment is only available on self-managed instances.')
        end

        it 'tracks the failure with the enrollment_failed label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_add_on_enable_failed')
            .with(
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'enrollment_failed' }
            )
            .and not_trigger_internal_events('secrets_manager_add_on_enabled')
        end
      end
    end

    context 'when on-demand billing is not accepted' do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial_eligible, on_demand_enabled: false))
      end

      it 'rejects without recording intent', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::ON_DEMAND_DISABLED_ERROR)
        expect(settings.secrets_manager_instance_enrolled).to be false
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end

      it 'tracks the failure with the on_demand_disabled label' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_add_on_enable_failed')
          .with(
            user: current_user,
            category: described_class.name,
            additional_properties: { label: 'on_demand_disabled' }
          )
          .and not_trigger_internal_events('secrets_manager_add_on_enabled')
      end
    end

    context 'when the instance is not in an eligible state' do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_return(::SecretsManagement::Entitlement.new(state: :trial))
      end

      it 'rejects as ineligible without recording intent', :aggregate_failures do
        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::INELIGIBLE_ERROR)
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end
    end

    context 'when the subscription service is unreachable' do
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
          an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error)
        )

        resolve
      end

      context 'when the intent was recorded before the post-intent resolve failed' do
        before do
          # `and_invoke` sequences the calls; `and_return(...).and_raise(...)`
          # would raise on the first call and never record the intent.
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(nil, user: current_user)
            .and_invoke(
              ->(*) { eligible_entitlement },
              ->(*) { raise ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom' }
            )
        end

        it 'reverts the intent so a failed click does not linger', :aggregate_failures do
          # Proves the failure happened after the stamp, not before it.
          expect(::SecretsManagement::InstanceEnrollment).to receive(:stamp_add_on_intent!).and_call_original

          result = resolve

          expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
          expect(settings.secrets_manager_instance_enrolled).to be false
          expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
        end
      end
    end

    # Anything the CDot-specific rescue does not name (a malformed CDot body,
    # a database error while re-resolving) must still not leave a stamp behind.
    context 'when an unexpected error is raised after the intent was recorded' do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_invoke(->(*) { eligible_entitlement }, ->(*) { raise StandardError, 'boom' })
      end

      it 'reverts the intent and re-raises', :aggregate_failures do
        # Proves the failure happened after the stamp, not before it.
        expect(::SecretsManagement::InstanceEnrollment).to receive(:stamp_add_on_intent!).and_call_original

        expect { resolve }.to raise_error(StandardError, 'boom')

        expect(settings.secrets_manager_instance_enrolled).to be false
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end
    end

    context 'on an offline environment or legacy license' do
      let(:license) do
        instance_double(License, online_cloud_license?: false, trial?: false, feature_available?: false, plan: nil)
      end

      it 'rejects with the offline error and never resolves the entitlement', :aggregate_failures do
        expect(client).not_to receive(:expire_secrets_manager_cache)
        expect(::SecretsManagement::Entitlement).not_to receive(:for!)

        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::OFFLINE_ERROR)
      end

      it 'tracks the failure with the offline label' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_add_on_enable_failed')
          .with(
            user: current_user,
            category: described_class.name,
            additional_properties: { label: 'offline' }
          )
          .and not_trigger_internal_events('secrets_manager_add_on_enabled')
      end
    end

    # No license means the licensed feature is unavailable, so the policy
    # denies before any license-shape check in the mutation could run.
    context 'on a self-managed install with no license' do
      let(:license) { nil }

      before do
        allow(::License).to receive(:feature_available?).and_call_original
      end

      it 'raises a resource not available error without resolving the entitlement' do
        expect(::SecretsManagement::Entitlement).not_to receive(:for!)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the licensed feature is not available' do
      before do
        allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(false)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the current user is not an admin' do
      let(:current_user) { user }

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'raises a resource not available error' do
        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end
  end
end
