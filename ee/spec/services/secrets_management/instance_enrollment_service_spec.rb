# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::InstanceEnrollmentService, feature_category: :secrets_management do
  let_it_be(:user) { create(:user) }

  subject(:service) { described_class.new(current_user: user) }

  describe '#enroll' do
    context 'when not on GitLab.com' do
      it 'enables the instance setting', :aggregate_failures do
        result = service.enroll

        expect(result).to be_success
        expect(Gitlab::CurrentSettings.secrets_manager_instance_enrolled).to be true
      end

      it 'expires the application settings cache so the new value is visible immediately' do
        expect(Gitlab::CurrentSettings).to receive(:expire_current_application_settings).and_call_original

        service.enroll
      end

      # `.clear_cache` has its own behavioural spec in the resolver spec; here we
      # only pin that enrollment drops the install-wide entitlement entry.
      it 'clears the cached entitlement so the beta window is recomputed' do
        expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache).with(nil).and_call_original

        service.enroll
      end

      # Mirrors the SaaS rule: enrolling before the paid experience reaches the
      # instance is what makes it part of the free beta cohort.
      describe 'beta marker' do
        it 'marks the instance as beta-enrolled while the paid experience is off' do
          stub_feature_flags(secrets_manager_paid_experience: false)

          service.enroll

          expect(Gitlab::CurrentSettings.secrets_manager_instance_beta_enrolled).to be true
        end

        it 'does not mark the instance as beta-enrolled once the paid experience is on' do
          stub_feature_flags(secrets_manager_paid_experience: true)

          service.enroll

          expect(Gitlab::CurrentSettings.secrets_manager_instance_beta_enrolled).to be false
        end

        it 're-evaluates the marker when an instance re-enrolls after the paid experience started' do
          Gitlab::CurrentSettings.update!(
            secrets_manager_instance_enrolled: false,
            secrets_manager_instance_beta_enrolled: true
          )
          stub_feature_flags(secrets_manager_paid_experience: true)

          service.enroll

          expect(Gitlab::CurrentSettings.secrets_manager_instance_beta_enrolled).to be false
        end
      end

      it 'creates an audit event' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          a_hash_including(
            name: 'secrets_manager_instance_enroll',
            author: user,
            scope: an_instance_of(::Gitlab::Audit::InstanceScope),
            target: an_instance_of(::Gitlab::Audit::InstanceScope),
            message: 'Enrolled instance in Secrets Manager'
          )
        )

        service.enroll
      end

      context 'when instance is already enrolled' do
        before do
          stub_application_setting(secrets_manager_instance_enrolled: true)
        end

        it 'returns an error', :aggregate_failures do
          result = service.enroll

          expect(result).to be_error
          expect(result.message).to eq('Instance is already enrolled.')
        end

        it 'does not create an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          service.enroll
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns an error', :aggregate_failures do
        result = service.enroll

        expect(result).to be_error
        expect(result.message).to eq('Instance enrollment is only available on self-managed instances.')
      end

      it 'does not enable the instance setting' do
        service.enroll

        expect(Gitlab::CurrentSettings.secrets_manager_instance_enrolled).to be false
      end
    end
  end

  describe '#unenroll' do
    context 'when not on GitLab.com' do
      context 'when instance is enrolled' do
        before do
          Gitlab::CurrentSettings.update!(secrets_manager_instance_enrolled: true)
        end

        it 'disables the instance setting', :aggregate_failures do
          result = service.unenroll

          expect(result).to be_success
          expect(Gitlab::CurrentSettings.secrets_manager_instance_enrolled).to be false
        end

        context 'when the paid add-on intent is recorded' do
          before do
            Gitlab::CurrentSettings.update!(secrets_manager_instance_add_on_requested_at: 1.day.ago)
          end

          it 'clears the add-on intent so a later re-enroll does not restore the paid state' do
            service.unenroll

            expect(Gitlab::CurrentSettings.secrets_manager_instance_add_on_requested_at).to be_nil
          end
        end

        it 'expires the application settings cache so the new value is visible immediately' do
          expect(Gitlab::CurrentSettings).to receive(:expire_current_application_settings).and_call_original

          service.unenroll
        end

        it 'clears the cached entitlement so the beta window is recomputed' do
          expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache).with(nil).and_call_original

          service.unenroll
        end

        it 'creates an audit event' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            a_hash_including(
              name: 'secrets_manager_instance_unenroll',
              author: user,
              scope: an_instance_of(::Gitlab::Audit::InstanceScope),
              target: an_instance_of(::Gitlab::Audit::InstanceScope),
              message: 'Unenrolled instance from Secrets Manager'
            )
          )

          service.unenroll
        end
      end

      context 'when instance is not enrolled' do
        it 'returns a not found error', :aggregate_failures do
          result = service.unenroll

          expect(result).to be_error
          expect(result.message).to eq('Instance is not enrolled.')
          expect(result.reason).to eq(:not_found)
        end

        it 'does not create an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          service.unenroll
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns an error', :aggregate_failures do
        result = service.unenroll

        expect(result).to be_error
        expect(result.message).to eq('Instance enrollment is only available on self-managed instances.')
      end
    end
  end

  describe '#enroll_with_add_on_intent' do
    subject(:result) { service.enroll_with_add_on_intent }

    def settings
      Gitlab::CurrentSettings.current_application_settings
    end

    context 'when the instance is not enrolled' do
      it 'enrolls the instance and stamps the intent', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload[:stamped]).to be true
        expect(result.payload[:rollback]).to eq(enrolled: true, stamped: true)
        expect(settings.secrets_manager_instance_enrolled).to be true
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_present
      end

      # The decision comes from the guarded write, not from the read at the
      # start of the call: a stamp that lands in between must not be claimed.
      context 'when a concurrent request stamps the intent before this call writes it' do
        let(:concurrent_requested_at) { 5.seconds.ago.change(usec: 0) }

        before do
          allow(::SecretsManagement::InstanceEnrollment).to receive(:stamp_add_on_intent!).and_wrap_original do |m|
            ::ApplicationSetting.where(id: settings.id)
              .update_all(secrets_manager_instance_add_on_requested_at: concurrent_requested_at)
            m.call
          end
        end

        it 'does not claim the conversion and leaves the other stamp intact', :aggregate_failures do
          expect(result).to be_success
          expect(result.payload[:stamped]).to be false
          expect(result.payload[:rollback]).to eq(enrolled: true, stamped: false)
          expect(settings.secrets_manager_instance_add_on_requested_at).to eq(concurrent_requested_at)
        end
      end

      it 'audits the enrollment but not the conversion', :aggregate_failures do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

        result

        expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
          a_hash_including(name: 'secrets_manager_instance_enroll')
        )
        expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(
          a_hash_including(name: 'secrets_manager_add_on_enable')
        )
      end

      context 'when stamping the intent fails' do
        before do
          allow(::SecretsManagement::InstanceEnrollment).to receive(:stamp_add_on_intent!)
            .and_raise(ActiveRecord::StatementInvalid, 'boom')
        end

        it 'reverts the enrollment it created and re-raises', :aggregate_failures do
          expect { result }.to raise_error(ActiveRecord::StatementInvalid)

          expect(settings.secrets_manager_instance_enrolled).to be false
          expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
        end
      end
    end

    context 'when the instance is already enrolled' do
      before do
        Gitlab::CurrentSettings.update!(secrets_manager_instance_enrolled: true)
      end

      it 'stamps the intent without re-enrolling', :aggregate_failures do
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        expect(result).to be_success
        expect(result.payload[:stamped]).to be true
        expect(result.payload[:rollback]).to eq(enrolled: false, stamped: true)
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_present
      end

      context 'when the intent is already stamped' do
        let(:existing_requested_at) { 2.days.ago.change(usec: 0) }

        before do
          Gitlab::CurrentSettings.update!(secrets_manager_instance_add_on_requested_at: existing_requested_at)
        end

        it 'keeps the original timestamp and reports nothing stamped', :aggregate_failures do
          expect(result).to be_success
          expect(result.payload[:stamped]).to be false
          expect(result.payload[:rollback]).to eq(enrolled: false, stamped: false)
          expect(settings.secrets_manager_instance_add_on_requested_at).to eq(existing_requested_at)
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns an error without touching the settings', :aggregate_failures do
        expect(result).to be_error
        expect(result.message).to eq('Instance enrollment is only available on self-managed instances.')
        expect(settings.secrets_manager_instance_enrolled).to be false
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end
    end
  end

  describe '#revert_add_on_intent' do
    def settings
      Gitlab::CurrentSettings.current_application_settings
    end

    before do
      Gitlab::CurrentSettings.update!(
        secrets_manager_instance_enrolled: true,
        secrets_manager_instance_add_on_requested_at: Time.current
      )
    end

    it 'clears the cached instance entitlement' do
      expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache).with(nil)

      service.revert_add_on_intent(enrolled: false, stamped: true)
    end

    context 'when the enable flow enrolled the instance' do
      let(:rollback) { { enrolled: true, stamped: true } }

      it 'unenrolls the instance and clears the intent', :aggregate_failures do
        expect(service.revert_add_on_intent(rollback)).to be_success

        expect(settings.secrets_manager_instance_enrolled).to be false
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end

      it 'audits the reverted enrollment' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          a_hash_including(
            name: 'secrets_manager_instance_unenroll',
            author: user,
            scope: an_instance_of(::Gitlab::Audit::InstanceScope),
            message: 'Reverted Secrets Manager enrollment after failed add-on enable'
          )
        )

        service.revert_add_on_intent(rollback)
      end
    end

    context 'when the instance was enrolled before the click' do
      let(:rollback) { { enrolled: false, stamped: true } }

      it 'keeps the enrollment, clears the intent and does not audit', :aggregate_failures do
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        expect(service.revert_add_on_intent(rollback)).to be_success

        expect(settings.secrets_manager_instance_enrolled).to be true
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
      end
    end

    # A request that changed nothing (re-click, or a sibling won both writes)
    # must not undo the sibling's enrollment or stamp when it fails later.
    context 'when this call neither enrolled nor stamped' do
      let(:rollback) { { enrolled: false, stamped: false } }

      it 'leaves the settings untouched and does not audit', :aggregate_failures do
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)
        expect(::Gitlab::CurrentSettings).not_to receive(:update!)

        expect(service.revert_add_on_intent(rollback)).to be_success

        expect(settings.secrets_manager_instance_enrolled).to be true
        expect(settings.secrets_manager_instance_add_on_requested_at).to be_present
      end
    end
  end

  describe '#audit_add_on_conversion' do
    it 'audits the paid conversion at instance scope' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        a_hash_including(
          name: 'secrets_manager_add_on_enable',
          author: user,
          scope: an_instance_of(::Gitlab::Audit::InstanceScope),
          target: an_instance_of(::Gitlab::Audit::InstanceScope),
          message: 'Enabled Secrets Manager paid add-on'
        )
      )

      service.audit_add_on_conversion
    end

    # The intent is already stamped and billable by the time this runs, so a
    # failed audit write is reported, not surfaced as a failed mutation.
    context 'when the audit write fails' do
      before do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(ActiveRecord::StatementInvalid, 'boom')
      end

      it 'reports the failure to Sentry and does not raise' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(ActiveRecord::StatementInvalid))

        expect { service.audit_add_on_conversion }.not_to raise_error
      end
    end
  end
end
