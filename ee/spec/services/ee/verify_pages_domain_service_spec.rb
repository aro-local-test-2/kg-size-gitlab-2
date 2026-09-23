# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VerifyPagesDomainService, feature_category: :pages do
  using RSpec::Parameterized::TableSyntax

  let(:current_user) { nil }
  let(:service) { described_class.new(domain, current_user) }

  describe '#execute' do
    subject(:service_response) { service.execute }

    context 'when successful verification' do
      shared_examples 'schedules Groups::EnterpriseUsers::BulkAssociateByDomainWorker' do
        it_behaves_like 'returning a success service response'

        it 'schedules Groups::EnterpriseUsers::BulkAssociateByDomainWorker', :aggregate_failures do
          expect(Groups::EnterpriseUsers::BulkAssociateByDomainWorker).to receive(:perform_async).with(domain.id)

          service_response

          expect(domain).to be_verified
        end
      end

      context 'when domain is disabled(or new)' do
        let(:domain) { create(:pages_domain, :disabled) }

        before do
          stub_resolver(domain.domain => ['something else', domain.verification_code])
        end

        include_examples 'schedules Groups::EnterpriseUsers::BulkAssociateByDomainWorker'
      end

      context 'when domain is verified' do
        let(:domain) { create(:pages_domain) }

        before do
          stub_resolver(domain.domain => ['something else', domain.verification_code])
        end

        include_examples 'schedules Groups::EnterpriseUsers::BulkAssociateByDomainWorker'
      end
    end

    context 'when unsuccessful verification' do
      shared_examples 'does not schedule Groups::EnterpriseUsers::BulkAssociateByDomainWorker' do
        it_behaves_like 'returning an error service response'
        it { is_expected.to have_attributes message: "Couldn't verify #{domain.domain}" }

        it 'does not schedule Groups::EnterpriseUsers::BulkAssociateByDomainWorker', :aggregate_failures do
          expect(Groups::EnterpriseUsers::BulkAssociateByDomainWorker).not_to receive(:perform_async)

          service_response

          expect(domain).not_to be_verified
        end
      end

      context 'when domain is disabled(or new)' do
        let(:domain) { create(:pages_domain, :disabled) }

        include_examples 'does not schedule Groups::EnterpriseUsers::BulkAssociateByDomainWorker'
      end

      context 'when domain is verified' do
        let(:domain) { create(:pages_domain) }

        include_examples 'does not schedule Groups::EnterpriseUsers::BulkAssociateByDomainWorker'
      end
    end

    describe 'audit events' do
      let_it_be(:user) { create(:user) }

      let_it_be(:project) { create(:project, :in_group) }
      let(:current_user) { user }
      let!(:domain) { create(:pages_domain, *[factory].compact, project: project) }

      context 'when licensed' do
        where(:factory, :verification_succeeds, :expected_event) do
          nil         | true  | nil
          nil         | false | :verification_failed
          :reverify   | true  | nil
          :reverify   | false | :verification_failed
          :unverified | true  | :verification_succeeded
          :unverified | false | nil
          :expired    | true  | nil
          :expired    | false | :disabled
          :disabled   | true  | :enabled
          :disabled   | false | nil
        end

        with_them do
          before do
            stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
            stub_resolver(verification_succeeds ? { domain.domain => domain.verification_code } : {})
          end

          it 'creates an audit event when the domain changes state', :aggregate_failures do
            if expected_event
              expect { service.execute }.to change { AuditEventReader.count }.by(1)

              expect(AuditEventReader.last).to have_attributes(
                author: user,
                entity_id: project.id,
                entity_type: 'Project',
                target_id: project.id,
                target_type: 'Project',
                target_details: domain.domain,
                details: include(
                  event_name: "pages_domain_#{expected_event}",
                  custom_message: "Domain #{expected_event.to_s.humanize(capitalize: false)} - #{domain.domain}"
                )
              )
            else
              expect { service.execute }.not_to change { AuditEventReader.count }
            end
          end
        end

        describe 'audit event author' do
          let!(:domain) { create(:pages_domain, :unverified, project: project) }

          before do
            stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
            stub_resolver(domain.domain => domain.verification_code)
          end

          context 'when a user initiated the verification' do
            it 'attributes the audit event to the user' do
              expect { service.execute }.to change { AuditEventReader.count }.by(1)

              expect(AuditEventReader.last.author).to eq(user)
            end
          end

          context 'when no user is given (for example, the verification worker)' do
            let(:current_user) { nil }

            it 'attributes the audit event to the system' do
              expect { service.execute }.to change { AuditEventReader.count }.by(1)

              expect(AuditEventReader.last.author_name).to eq('(System)')
            end
          end
        end

        context 'when the domain has no verification code' do
          let(:domain) { build(:pages_domain, project: project, verification_code: '') }

          before do
            stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
          end

          it 'does not track audit event', :aggregate_failures do
            expect(Resolv::DNS).not_to receive(:open)

            expect { service.execute }.not_to change { AuditEventReader.count }
          end
        end

        context 'when domain verification is disabled' do
          let!(:domain) { create(:pages_domain, :unverified, project: project) }
          let(:notification_service) { instance_double(NotificationService) }

          before do
            stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
            stub_application_setting(pages_domain_verification_enabled: false)
            allow(NotificationService).to receive(:new).and_return(notification_service)
          end

          it 'audits the state change even though the email notification is skipped', :aggregate_failures do
            expect(Resolv::DNS).not_to receive(:open)
            expect(notification_service).not_to receive(:pages_domain_verification_succeeded)

            expect { service.execute }.to change { AuditEventReader.count }.by(1)

            expect(AuditEventReader.last).to have_attributes(
              author: user,
              entity_id: project.id,
              entity_type: 'Project',
              target_details: domain.domain,
              details: include(event_name: 'pages_domain_verification_succeeded')
            )
          end
        end
      end

      context 'when unlicensed' do
        where(:factory, :verification_succeeds, :attempted_event) do
          :disabled   | true  | :enabled
          :unverified | true  | :verification_succeeded
          nil         | false | :verification_failed
          :expired    | false | :disabled
        end

        with_them do
          before do
            stub_licensed_features(admin_audit_log: false, audit_events: false, extended_audit_events: false)
            stub_resolver(verification_succeeds ? { domain.domain => domain.verification_code } : {})
          end

          it 'does not track audit event', :aggregate_failures do
            expect(::Gitlab::Audit::Auditor).to receive(:audit)
              .with(a_hash_including(name: "pages_domain_#{attempted_event}"))
              .and_call_original

            expect { service.execute }.not_to change { AuditEventReader.count }
          end
        end
      end
    end
  end
end
