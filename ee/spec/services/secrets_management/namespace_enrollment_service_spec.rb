# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::NamespaceEnrollmentService, feature_category: :secrets_management do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }

  subject(:service) { described_class.new(group, current_user: user) }

  shared_examples 'enrollment not allowed' do |action|
    it 'returns a forbidden error', :aggregate_failures do
      result = service.public_send(action)

      expect(result).to be_error
      expect(result.message).to eq('Namespace enrollment is not allowed.')
      expect(result.reason).to eq(:forbidden)
    end

    it 'does not create an audit event' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      service.public_send(action)
    end
  end

  describe '#enroll' do
    context 'when on GitLab.com', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      it 'creates a namespace enrollment', :aggregate_failures do
        result = service.enroll

        expect(result).to be_success
        enrollment = result.payload[:enrollment]
        expect(enrollment.namespace).to eq(group)
      end

      it 'persists the enrollment record' do
        expect { service.enroll }
          .to change { SecretsManagement::NamespaceEnrollment.count }.by(1)
      end

      it 'creates an audit event' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          a_hash_including(
            name: 'secrets_manager_namespace_enroll',
            author: user,
            scope: group,
            target: group,
            message: 'Enrolled namespace in Secrets Manager'
          )
        )

        service.enroll
      end

      context 'when the paid experience is not enabled for the namespace' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: false)
        end

        it 'marks the enrollment as beta' do
          expect(service.enroll.payload[:enrollment].beta).to be true
        end
      end

      context 'when the paid experience is enabled for the namespace' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: group)
        end

        it 'does not mark the enrollment as beta' do
          expect(service.enroll.payload[:enrollment].beta).to be false
        end
      end

      context 'when namespace is already enrolled' do
        before_all do
          create(:secrets_manager_namespace_enrollment, namespace: group)
        end

        it 'returns an error', :aggregate_failures do
          result = service.enroll

          expect(result).to be_error
          expect(result.message).to eq('Namespace is already enrolled.')
        end

        it 'does not create an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          service.enroll
        end
      end

      context 'when the namespace previously opted out' do
        let_it_be_with_reload(:enrollment) do
          create(:secrets_manager_namespace_enrollment, :disabled, namespace: group, beta: true)
        end

        before do
          stub_feature_flags(secrets_manager_paid_experience: group)
        end

        it 'enables the existing record instead of creating another', :aggregate_failures do
          expect { service.enroll }
            .not_to change { SecretsManagement::NamespaceEnrollment.count }

          expect(enrollment.reload).to be_enabled
        end

        it 're-evaluates the beta cohort' do
          service.enroll

          expect(enrollment.reload.beta).to be false
        end

        it 'creates an audit event' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            a_hash_including(name: 'secrets_manager_namespace_enroll')
          )

          service.enroll
        end
      end

      context 'when namespace is a user namespace' do
        let_it_be(:user_namespace) { create(:user_namespace) }

        subject(:service) { described_class.new(user_namespace, current_user: user) }

        it_behaves_like 'enrollment not allowed', :enroll

        it 'does not create an enrollment record' do
          expect { service.enroll }
            .not_to change { SecretsManagement::NamespaceEnrollment.count }
        end
      end

      context 'when namespace is not a root group' do
        let_it_be(:subgroup) { create(:group, parent: group) }
        let_it_be(:nested_subgroup) { create(:group, parent: subgroup) }

        it 'rejects a subgroup', :aggregate_failures do
          result = described_class.new(subgroup, current_user: user).enroll

          expect(result).to be_error
          expect(result.message).to eq('Namespace enrollment is not allowed.')
        end

        it 'rejects a deeply nested subgroup', :aggregate_failures do
          result = described_class.new(nested_subgroup, current_user: user).enroll

          expect(result).to be_error
          expect(result.message).to eq('Namespace enrollment is not allowed.')
        end

        it 'does not create an enrollment record' do
          expect { described_class.new(subgroup, current_user: user).enroll }
            .not_to change { SecretsManagement::NamespaceEnrollment.count }
        end
      end

      context 'when license is not available' do
        before do
          stub_licensed_features(native_secrets_management: false)
        end

        it_behaves_like 'enrollment not allowed', :enroll
      end

      context 'when enrollment feature flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_namespace_enrollment: false)
        end

        it_behaves_like 'enrollment not allowed', :enroll
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      it_behaves_like 'enrollment not allowed', :enroll

      it 'does not create an enrollment record' do
        expect { service.enroll }
          .not_to change { SecretsManagement::NamespaceEnrollment.count }
      end
    end
  end

  describe '#unenroll' do
    context 'when on GitLab.com', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      context 'when the paid experience is enabled for the namespace' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: group)
        end

        context 'when namespace is enrolled' do
          let_it_be_with_reload(:enrollment) do
            create(:secrets_manager_namespace_enrollment, namespace: group)
          end

          it 'disables the enrollment record instead of deleting it', :aggregate_failures do
            result = service.unenroll

            expect(result).to be_success
            expect(enrollment.reload).not_to be_enabled
            expect(SecretsManagement::NamespaceEnrollment.enrolled?(group)).to be false
          end

          it 'keeps the enrollment record' do
            expect { service.unenroll }
              .not_to change { SecretsManagement::NamespaceEnrollment.count }
          end

          context 'with a recorded add-on intent' do
            before do
              enrollment.update!(add_on_requested_at: Time.current)
            end

            it 'clears the intent so a later re-enroll cannot restore the paid state' do
              expect { service.unenroll }
                .to change { enrollment.reload.add_on_requested_at }.to(nil)
            end

            # CI job registration caches the entitlement across requests; a stale
            # paid answer would keep granting secrets access after the opt-out.
            it 'clears the cached entitlement' do
              expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache).with(group)

              service.unenroll
            end
          end

          it 'creates an audit event' do
            expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
              a_hash_including(
                name: 'secrets_manager_namespace_unenroll',
                author: user,
                scope: group,
                target: group,
                message: 'Unenrolled namespace from Secrets Manager'
              )
            )

            service.unenroll
          end
        end

        # The paid experience grants access to never-enrolled top-level groups, so
        # the opt-out has to be recorded even when there is no enrollment yet.
        context 'when namespace was never enrolled' do
          it 'records the opt-out', :aggregate_failures do
            expect { service.unenroll }
              .to change { SecretsManagement::NamespaceEnrollment.count }.by(1)

            expect(SecretsManagement::NamespaceEnrollment.opted_out?(group)).to be true
            expect(SecretsManagement::NamespaceEnrollment.find_by_namespace_id(group.id).beta).to be false
          end

          it 'creates an audit event' do
            expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
              a_hash_including(name: 'secrets_manager_namespace_unenroll')
            )

            service.unenroll
          end
        end

        context 'when namespace already opted out' do
          before_all do
            create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
          end

          it 'returns an error', :aggregate_failures do
            result = service.unenroll

            expect(result).to be_error
            expect(result.message).to eq('Namespace is already unenrolled.')
          end

          it 'does not create an audit event' do
            expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

            service.unenroll
          end
        end
      end

      # The free beta keeps the pre-paid-experience destroy behavior: outside
      # the paid experience the opt-out marker has no consumer.
      context 'when the paid experience is not enabled for the namespace' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: false)
        end

        context 'when namespace is enrolled' do
          let_it_be_with_reload(:enrollment) do
            create(:secrets_manager_namespace_enrollment, namespace: group)
          end

          it 'destroys the enrollment record', :aggregate_failures do
            result = nil

            expect { result = service.unenroll }
              .to change { SecretsManagement::NamespaceEnrollment.count }.by(-1)

            expect(result).to be_success
            expect(SecretsManagement::NamespaceEnrollment.find_by_namespace_id(group.id)).to be_nil
          end

          it 'clears the cached entitlement' do
            expect(::SecretsManagement::Entitlement::Resolver).to receive(:clear_cache).with(group)

            service.unenroll
          end

          it 'creates an audit event' do
            expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
              a_hash_including(name: 'secrets_manager_namespace_unenroll')
            )

            service.unenroll
          end
        end

        context 'when namespace is not enrolled' do
          it 'returns a not found error', :aggregate_failures do
            result = service.unenroll

            expect(result).to be_error
            expect(result.message).to eq('Enrollment not found.')
            expect(result.reason).to eq(:not_found)
          end

          it 'does not record an opt-out' do
            expect { service.unenroll }
              .not_to change { SecretsManagement::NamespaceEnrollment.count }
          end

          it 'does not create an audit event' do
            expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

            service.unenroll
          end
        end
      end

      context 'when namespace is a user namespace' do
        let_it_be(:user_namespace) { create(:user_namespace) }

        subject(:service) { described_class.new(user_namespace, current_user: user) }

        it_behaves_like 'enrollment not allowed', :unenroll
      end

      context 'when namespace is not a root group' do
        let_it_be(:subgroup) { create(:group, parent: group) }

        subject(:service) { described_class.new(subgroup, current_user: user) }

        it_behaves_like 'enrollment not allowed', :unenroll
      end

      context 'when license is not available' do
        before do
          stub_licensed_features(native_secrets_management: false)
        end

        it_behaves_like 'enrollment not allowed', :unenroll
      end

      context 'when enrollment feature flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_namespace_enrollment: false)
        end

        it_behaves_like 'enrollment not allowed', :unenroll
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      it_behaves_like 'enrollment not allowed', :unenroll
    end
  end

  describe '#enroll_with_add_on_intent' do
    context 'when on GitLab.com', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      context 'when the namespace is not enrolled' do
        it 'enrolls and stamps the intent, with a destroy rollback token', :aggregate_failures do
          result = service.enroll_with_add_on_intent

          expect(result).to be_success
          expect(result.payload[:rollback]).to eq(:destroy)
          expect(result.payload[:enrollment].add_on_requested_at).to be_present
          expect(result.payload[:stamped]).to be(true)
        end
      end

      context 'when stamping the intent fails after a fresh enroll' do
        before do
          # The first found instance is the post-enroll refetch: the fresh
          # enroll builds its record via `new`, so it is never "found".
          allow_next_found_instance_of(SecretsManagement::NamespaceEnrollment) do |enrollment|
            allow(enrollment).to receive(:update!).and_raise(ActiveRecord::StatementInvalid)
          end
        end

        it 'compensates the enroll write, audits the undo, and re-raises', :aggregate_failures do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(name: 'secrets_manager_namespace_unenroll')
          )

          expect { service.enroll_with_add_on_intent }.to raise_error(ActiveRecord::StatementInvalid)

          expect(SecretsManagement::NamespaceEnrollment.count).to eq(0)
        end
      end

      context 'when stamping raises a non-persistence error' do
        before do
          allow_next_found_instance_of(SecretsManagement::NamespaceEnrollment) do |enrollment|
            allow(enrollment).to receive(:update!).and_raise(NoMethodError, 'programming error')
          end
        end

        # Compensation is scoped to ActiveRecord errors so a bug is not masked
        # as a rollback: the error propagates and the enroll write is left as is.
        it 're-raises without compensating', :aggregate_failures do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit).with(
            hash_including(name: 'secrets_manager_namespace_unenroll')
          )

          expect { service.enroll_with_add_on_intent }.to raise_error(NoMethodError, 'programming error')

          expect(SecretsManagement::NamespaceEnrollment.count).to eq(1)
        end
      end

      context 'when stamping the intent fails after re-enabling an opted-out enrollment' do
        let_it_be(:opted_out_at) { 3.days.ago.change(usec: 0) }
        let_it_be_with_reload(:enrollment) do
          create(:secrets_manager_namespace_enrollment, namespace: group, disabled_at: opted_out_at)
        end

        before do
          # Only the stamp write (the lone add_on_requested_at key) may fail;
          # the re-enable and the revert writes must go through.
          allow(SecretsManagement::NamespaceEnrollment).to receive(:find_by_namespace_id)
            .and_wrap_original do |find, *args|
            find.call(*args)&.tap do |found|
              allow(found).to receive(:update!).and_wrap_original do |update, *attrs|
                raise ActiveRecord::StatementInvalid if attrs.first&.keys&.map(&:to_sym) == [:add_on_requested_at]

                update.call(*attrs)
              end
            end
          end
        end

        it 'restores the opt-out instead of destroying the record, audits the undo, and re-raises',
          :aggregate_failures do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              name: 'secrets_manager_namespace_unenroll',
              message: 'Reverted Secrets Manager enrollment after failed add-on enable'
            )
          )

          expect { service.enroll_with_add_on_intent }.to raise_error(ActiveRecord::StatementInvalid)

          expect(SecretsManagement::NamespaceEnrollment.count).to eq(1)
          expect(enrollment.disabled_at).to eq(opted_out_at)
          expect(enrollment.add_on_requested_at).to be_nil
        end
      end

      context 'when the namespace is already enrolled' do
        let_it_be_with_reload(:enrollment) do
          create(:secrets_manager_namespace_enrollment, namespace: group)
        end

        it 'stamps the intent and captures the pre-call shape', :aggregate_failures do
          result = service.enroll_with_add_on_intent

          expect(result).to be_success
          expect(result.payload[:rollback]).to include('disabled_at' => nil, 'add_on_requested_at' => nil)
          expect(enrollment.reload.add_on_requested_at).to be_present
        end

        it 'does not re-stamp an existing intent and reports it', :aggregate_failures do
          timestamp = 2.days.ago
          enrollment.update!(add_on_requested_at: timestamp)

          result = nil
          expect { result = service.enroll_with_add_on_intent }
            .not_to change { enrollment.reload.add_on_requested_at }
          expect(result.payload[:stamped]).to be(false)
        end
      end

      context 'when enrollment is forbidden' do
        before do
          stub_feature_flags(secrets_manager_namespace_enrollment: false)
        end

        it 'propagates the error without writing', :aggregate_failures do
          result = service.enroll_with_add_on_intent

          expect(result).to be_error
          expect(result.reason).to eq(:forbidden)
          expect(SecretsManagement::NamespaceEnrollment.count).to eq(0)
        end
      end
    end
  end

  describe '#revert_add_on_intent' do
    context 'when on GitLab.com', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_feature_flags(secrets_manager_namespace_enrollment: group)
      end

      it 'destroys the record for a :destroy token' do
        service.enroll_with_add_on_intent

        expect { service.revert_add_on_intent(:destroy) }
          .to change { SecretsManagement::NamespaceEnrollment.count }.by(-1)
      end

      it 'audits the undone enrollment for a :destroy token' do
        service.enroll_with_add_on_intent

        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'secrets_manager_namespace_unenroll',
            message: 'Reverted Secrets Manager enrollment after failed add-on enable'
          )
        )

        service.revert_add_on_intent(:destroy)
      end

      it 'restores the captured shape for a snapshot token and audits the undo', :aggregate_failures do
        enrollment = create(
          :secrets_manager_namespace_enrollment, namespace: group, disabled_at: 3.days.ago
        )
        rollback = service.enroll_with_add_on_intent.payload[:rollback]

        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(name: 'secrets_manager_namespace_unenroll')
        )

        service.revert_add_on_intent(rollback)

        expect(enrollment.reload).not_to be_enabled
        expect(enrollment.add_on_requested_at).to be_nil
      end

      it 'does not audit when the enrollment predates the click and only the intent is cleared' do
        create(:secrets_manager_namespace_enrollment, namespace: group)
        rollback = service.enroll_with_add_on_intent.payload[:rollback]

        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        service.revert_add_on_intent(rollback)
      end

      it 'is a no-op when no enrollment exists' do
        expect(service.revert_add_on_intent(:destroy)).to be_success
      end
    end
  end

  describe '#audit_add_on_conversion' do
    it 'audits the paid conversion' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(
          name: 'secrets_manager_add_on_enable',
          message: 'Enabled Secrets Manager paid add-on'
        )
      )

      service.audit_add_on_conversion
    end
  end
end
