# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::SecretsManagement::InstanceStartTrial, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:admin) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:instance_id) { ::Gitlab::CurrentSettings.uuid }
  let(:license) { instance_double(License, online_cloud_license?: true, feature_available?: true, plan: nil) }

  let(:trial_eligible_entitlement) { ::SecretsManagement::Entitlement.new(state: :trial_eligible) }
  let(:trial_entitlement) { ::SecretsManagement::Entitlement.new(state: :trial, credits_remaining: 500) }

  let(:success_response) do
    ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(success: true)
  end

  subject(:mutation) { described_class.new(context: query_context, object: nil, field: nil) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_licensed_features(native_secrets_management: true)
    allow(::License).to receive(:current).and_return(license)
  end

  def resolve
    mutation.resolve
  end

  describe '#resolve', :enable_admin_mode do
    context 'when the instance is trial eligible and CDot starts the trial' do
      before do
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_return(trial_eligible_entitlement, trial_entitlement)
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(client).to receive(:start_secrets_manager_trial)
          .with(instance_id: instance_id).and_return(success_response)
      end

      it 'returns the post-trial entitlement with no errors', :aggregate_failures do
        result = resolve

        expect(result[:errors]).to be_empty
        expect(result[:entitlement]).to be_a(::Types::SecretsManagement::EntitlementType::Adapter)
        expect(result[:entitlement].state).to eq(:trial)
        expect(result[:entitlement].group).to be_nil
      end

      it 'starts the trial on CDot by instance id' do
        resolve

        expect(client).to have_received(:start_secrets_manager_trial).with(instance_id: instance_id)
      end

      it 'enrolls the instance in Secrets Manager' do
        expect { resolve }
          .to change { ::Gitlab::CurrentSettings.secrets_manager_instance_enrolled }.from(false).to(true)
      end

      it 'audits the trial start with an instance scope' do
        # Already enrolled, so the enrollment service does not audit too.
        stub_application_setting(secrets_manager_instance_enrolled: true)

        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          a_hash_including(
            name: 'secrets_manager_instance_trial_start',
            author: current_user,
            scope: an_instance_of(::Gitlab::Audit::InstanceScope),
            target: an_instance_of(::Gitlab::Audit::InstanceScope),
            message: 'Started the instance-wide Secrets Manager trial'
          )
        ).and_call_original

        resolve
      end

      context 'when the audit write fails' do
        before do
          stub_application_setting(secrets_manager_instance_enrolled: true)
          allow(::Gitlab::Audit::Auditor).to receive(:audit)
            .and_raise(ActiveRecord::ConnectionNotEstablished, 'db down')
        end

        # CDot has already started the trial, so an audit failure must not fail the mutation.
        it 'reports the failure and still returns the entitlement', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_instance_of(ActiveRecord::ConnectionNotEstablished))

          result = resolve

          expect(result[:entitlement].state).to eq(:trial)
          expect(result[:errors]).to be_empty
        end

        it 'still tracks the trial as started' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_instance_trial_started')
            .with(user: current_user, category: described_class.name)
        end
      end

      it 'tracks the secrets_manager_instance_trial_started event' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_instance_trial_started')
          .with(user: current_user, category: described_class.name)
          .and not_trigger_internal_events('secrets_manager_instance_trial_start_failed')
      end

      it 'expires both entitlement cache layers before each entitlement read' do
        # Already enrolled: InstanceEnrollmentService clears the resolver cache on its own.
        stub_application_setting(secrets_manager_instance_enrolled: true)

        calls = []
        allow(client).to receive(:expire_secrets_manager_cache).with(instance_id: instance_id) { calls << :expire_cdot }
        allow(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache).with(nil) { calls << :clear_resolver }
        allow(::SecretsManagement::Entitlement).to receive(:for!).with(nil, user: current_user) do
          calls << :resolve
          calls.count(:resolve) == 1 ? trial_eligible_entitlement : trial_entitlement
        end
        allow(client).to receive(:start_secrets_manager_trial).with(instance_id: instance_id) do
          calls << :start_trial
          success_response
        end

        resolve

        # Live pre-check, CDot POST, then a fresh post-trial read.
        expect(calls).to eq(
          %i[expire_cdot clear_resolver resolve start_trial expire_cdot clear_resolver resolve]
        )
      end

      context 'when the instance is already enrolled' do
        before do
          stub_application_setting(secrets_manager_instance_enrolled: true)
        end

        it 'does not enroll again and returns no errors', :aggregate_failures do
          expect(::SecretsManagement::InstanceEnrollmentService).not_to receive(:new)

          expect(resolve[:errors]).to be_empty
        end
      end

      context 'when enrollment fails' do
        before do
          allow_next_instance_of(::SecretsManagement::InstanceEnrollmentService) do |service|
            allow(service).to receive(:enroll).and_return(ServiceResponse.error(message: 'boom'))
          end
        end

        # CDot has already started the trial, so the mutation must still report it.
        it 'returns the entitlement alongside the enrollment error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement].state).to eq(:trial)
          expect(result[:errors]).to contain_exactly('boom')
        end

        it 'still tracks the trial as started' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_instance_trial_started')
            .with(user: current_user, category: described_class.name)
        end
      end

      context 'when the post-trial entitlement lookup raises' do
        before do
          # First call is the live pre-check, second is the post-trial lookup.
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(nil, user: current_user)
            .and_invoke(
              ->(*) { trial_eligible_entitlement },
              ->(*) { raise ActiveRecord::StatementInvalid, 'connection lost' }
            )
        end

        it 'reports the failure and returns a null entitlement with no errors', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_instance_of(ActiveRecord::StatementInvalid))

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to be_empty
        end
      end
    end

    context 'when the live entitlement is not trial eligible' do
      where(:state, :blocked_reason, :expected_reason, :expected_message) do
        [
          [:trial, nil, :trial_already_active, 'A Secrets Manager trial is already active for this instance.'],
          [:paid, nil, :ineligible, 'This instance is not eligible to start a Secrets Manager trial.'],
          [:blocked, :trial_expired, :ineligible, 'This instance is not eligible to start a Secrets Manager trial.'],
          [:ineligible, nil, :ineligible, 'This instance is not eligible to start a Secrets Manager trial.']
        ]
      end

      with_them do
        before do
          allow(client).to receive(:expire_secrets_manager_cache)
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(nil, user: current_user)
            .and_return(::SecretsManagement::Entitlement.new(state: state, blocked_reason: blocked_reason))
        end

        it 'rejects without calling CDot', :aggregate_failures do
          expect(client).not_to receive(:start_secrets_manager_trial)

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(expected_message)
        end

        it 'does not enroll the instance' do
          expect { resolve }.not_to change { ::Gitlab::CurrentSettings.secrets_manager_instance_enrolled }
        end

        it 'tracks the failure with the reason as label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_instance_trial_start_failed')
            .with(
              user: current_user,
              category: described_class.name,
              additional_properties: { label: expected_reason.to_s }
            )
            .and not_trigger_internal_events('secrets_manager_instance_trial_started')
        end
      end
    end

    context 'when CDot rejects the request' do
      def stub_trial_eligible_instance
        allow(client).to receive(:expire_secrets_manager_cache)
        allow(::SecretsManagement::Entitlement).to receive(:for!)
          .with(nil, user: current_user)
          .and_return(trial_eligible_entitlement)
      end

      where(:error_code, :expected_message) do
        [
          [:trial_already_active, 'A Secrets Manager trial is already active for this instance.'],
          [:not_found, 'This instance is not recognized by the subscription service.'],
          [:ineligible, 'This instance is not eligible to start a Secrets Manager trial.']
        ]
      end

      with_them do
        before do
          stub_trial_eligible_instance
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

        it 'does not enroll the instance' do
          expect { resolve }.not_to change { ::Gitlab::CurrentSettings.secrets_manager_instance_enrolled }
        end

        it 'tracks the failure with the error code as label' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_instance_trial_start_failed')
            .with(
              user: current_user,
              category: described_class.name,
              additional_properties: { label: error_code.to_s }
            )
            .and not_trigger_internal_events('secrets_manager_instance_trial_started')
        end
      end

      context 'when ineligible with a CDot-supplied message' do
        before do
          stub_trial_eligible_instance
          allow(client).to receive(:start_secrets_manager_trial).and_return(
            ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse.new(
              success: false, error_code: :ineligible, error_message: 'Instance already used its trial'
            )
          )
        end

        it 'surfaces the CDot message' do
          expect(resolve[:errors]).to contain_exactly('Instance already used its trial')
        end
      end
    end

    context 'when the subscription service is unreachable' do
      before do
        allow(client).to receive(:expire_secrets_manager_cache)
      end

      context 'when the live eligibility check fails' do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
        end

        it 'returns a generic unavailable error and never posts to CDot', :aggregate_failures do
          expect(client).not_to receive(:start_secrets_manager_trial)

          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
        end
      end

      context 'when the trial start fails' do
        before do
          allow(::SecretsManagement::Entitlement).to receive(:for!)
            .with(nil, user: current_user)
            .and_return(trial_eligible_entitlement)
          allow(client).to receive(:start_secrets_manager_trial)
            .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error, 'boom')
        end

        it 'returns a generic unavailable error', :aggregate_failures do
          result = resolve

          expect(result[:entitlement]).to be_nil
          expect(result[:errors]).to contain_exactly(described_class::UNAVAILABLE_ERROR)
        end

        it 'does not enroll the instance' do
          expect { resolve }.not_to change { ::Gitlab::CurrentSettings.secrets_manager_instance_enrolled }
        end

        it 'tracks the failure as unavailable' do
          expect { resolve }
            .to trigger_internal_events('secrets_manager_instance_trial_start_failed')
            .with(
              user: current_user,
              category: described_class.name,
              additional_properties: { label: 'unavailable' }
            )
            .and not_trigger_internal_events('secrets_manager_instance_trial_started')
        end

        it 'reports the failure to Sentry' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error)
          )

          resolve
        end
      end
    end

    context 'on an offline (air-gapped) install' do
      let(:license) { instance_double(License, online_cloud_license?: false, feature_available?: true, plan: nil) }

      it 'rejects with the offline error and never resolves or calls CDot', :aggregate_failures do
        expect(::SecretsManagement::Entitlement).not_to receive(:for!)
        expect(client).not_to receive(:start_secrets_manager_trial)

        result = resolve

        expect(result[:entitlement]).to be_nil
        expect(result[:errors]).to contain_exactly(described_class::OFFLINE_ERROR)
      end

      it 'tracks the failure as offline' do
        expect { resolve }
          .to trigger_internal_events('secrets_manager_instance_trial_start_failed')
          .with(
            user: current_user,
            category: described_class.name,
            additional_properties: { label: 'offline' }
          )
          .and not_trigger_internal_events('secrets_manager_instance_trial_started')
      end
    end

    context 'when the paid-experience feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the current user is not an admin' do
      let_it_be(:current_user) { create(:user) }

      it 'raises a resource not available error and never calls CDot' do
        expect(client).not_to receive(:start_secrets_manager_trial)

        expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end
  end

  describe '#resolve without admin mode' do
    it 'raises a resource not available error' do
      expect { resolve }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
    end
  end
end
