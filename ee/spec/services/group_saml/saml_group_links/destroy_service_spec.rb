# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GroupSaml::SamlGroupLinks::DestroyService, feature_category: :system_access do
  subject(:service) { described_class.new(current_user: current_user, group: group, saml_group_link: saml_group_link) }

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user) }
  let_it_be_with_refind(:saml_group_link) { create(:saml_group_link, group: group) }

  describe '#execute' do
    context 'when authorized user' do
      let_it_be(:saml_provider) { create(:saml_provider, group: group, enabled: true) }

      before_all do
        group.add_owner(current_user)
      end

      context 'when licensed features are available' do
        let(:audit_licensed) { true }

        before do
          stub_licensed_features(
            group_saml: true, saml_group_sync: true,
            admin_audit_log: audit_licensed, audit_events: audit_licensed, extended_audit_events: audit_licensed
          )
        end

        context 'when the record is destroyed' do
          it 'removes a saml_group_link from the group' do
            expect { service.execute }.to change { group.saml_group_links.count }.by(-1)
          end

          describe 'audit events' do
            context 'when audit events are licensed' do
              let(:audit_event_message) do
                "SAML group links removed. Group Name - #{saml_group_link.saml_group_name}"
              end

              it 'creates an audit event', :aggregate_failures do
                audit_context = {
                  name: 'saml_group_links_removed',
                  author: current_user,
                  scope: group,
                  target: group,
                  message: audit_event_message
                }
                expect(::Gitlab::Audit::Auditor).to receive(:audit).with(audit_context).once.and_call_original

                expect(service.execute).to be_success
                expect(AuditEventReader.count).to eq(1)
                expect(AuditEventReader.last.details[:custom_message]).to eq(audit_event_message)
              end
            end

            context 'when audit events are not licensed' do
              let(:audit_licensed) { false }

              it 'does not track audit event' do
                expect { service.execute }.not_to change { AuditEventReader.count }
              end
            end
          end

          describe 'scim_group_uid cleanup' do
            context 'when the saml_group_link has a scim_group_uid' do
              let_it_be_with_refind(:saml_group_link) do
                create(:saml_group_link, :with_scim_group_uid, group: group)
              end

              context 'when it is the only remaining saml_group_link for that scim_group_uid' do
                it 'enqueues CleanupScimGroupMembershipsWorker' do
                  expect(::Authn::CleanupScimGroupMembershipsWorker)
                    .to receive(:perform_async).with(saml_group_link.scim_group_uid)

                  service.execute
                end
              end

              context 'when other saml_group_links share the same scim_group_uid' do
                let_it_be(:other_group) { create(:group) }
                let_it_be(:other_link) do
                  create(:saml_group_link, group: other_group, scim_group_uid: saml_group_link.scim_group_uid)
                end

                it 'does not enqueue CleanupScimGroupMembershipsWorker' do
                  expect(::Authn::CleanupScimGroupMembershipsWorker).not_to receive(:perform_async)

                  service.execute
                end
              end
            end

            context 'when the saml_group_link has no scim_group_uid' do
              it 'does not enqueue CleanupScimGroupMembershipsWorker' do
                expect(::Authn::CleanupScimGroupMembershipsWorker).not_to receive(:perform_async)

                service.execute
              end
            end
          end
        end

        context 'when the record fails to destroy' do
          before do
            allow(saml_group_link).to receive(:destroy!).and_raise(
              ActiveRecord::RecordNotDestroyed.new('Failed to delete SamlGroupLink record', saml_group_link)
            )
          end

          it 'returns an error response with the exception message', :aggregate_failures do
            expect(::Authn::CleanupScimGroupMembershipsWorker).not_to receive(:perform_async)

            response = nil

            expect { response = service.execute }
              .to not_change { group.saml_group_links.count }
              .and not_change { AuditEventReader.count }
            expect(response).not_to be_success
            expect(response[:message]).to eq('Failed to delete SamlGroupLink record')
          end
        end
      end
    end

    context 'when user is not allowed to remove saml_group_links' do
      before do
        allow(Ability).to receive(:allowed?).with(current_user, :admin_saml_group_links, group).and_return(false)
      end

      it 'throws unauthorized error', :aggregate_failures do
        response = service.execute

        expect(response).not_to be_success
        expect(response[:message]).to eq('Unauthorized')
      end
    end
  end
end
