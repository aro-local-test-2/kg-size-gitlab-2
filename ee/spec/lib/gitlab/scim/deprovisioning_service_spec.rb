# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Gitlab::Scim::DeprovisioningService, feature_category: :system_access do
  describe '#execute' do
    let(:identity) { create(:scim_identity, active: true) }
    let(:user) { identity.user }

    let(:service) { described_class.new(identity) }

    context 'when user is successfully removed' do
      it 'deactivates scim identity' do
        expect { service.execute }.to change { identity.active }.from(true).to(false)
      end

      it 'blocks the user' do
        service.execute

        expect(user.ldap_blocked?).to be(true)
      end

      it 'returns the successful deprovision message' do
        response = service.execute

        expect(response.message).to include("User #{user.name} SCIM identity is deactivated")
      end

      context 'when licensed' do
        before do
          stub_licensed_features(admin_audit_log: true)
          service # eagerly create the identity/user so their own audit events don't get counted below
        end

        it 'creates an audit event', :aggregate_failures do
          expect { service.execute }.to change { AuditEvents::UserAuditEvent.count }.by(1)

          audit_event = AuditEvents::UserAuditEvent.order(:id).last
          expect(audit_event.user_id).to eq(user.id)
          expect(audit_event.details[:custom_message]).to eq('Blocked user by SCIM deprovisioning')
          expect(audit_event.details[:event_name]).to eq('user_blocked_by_scim_deprovisioning')
          expect(audit_event.details[:system_event]).to be true
          expect(audit_event.details[:reason]).to eq('deprovisioned via SCIM')
          expect(audit_event.details[:extern_uid]).to eq(identity.extern_uid)
        end

        it 'creates only one audit event across repeated deprovisioning attempts' do
          expect { service.execute }.to change { AuditEvents::UserAuditEvent.count }.by(1)
          expect { described_class.new(identity).execute }.not_to change { AuditEvents::UserAuditEvent.count }
        end
      end

      context 'when not licensed' do
        before do
          stub_licensed_features(admin_audit_log: false, audit_events: false, extended_audit_events: false)
        end

        it 'does not create an audit event' do
          expect { service.execute }.not_to change { AuditEvents::UserAuditEvent.count }
        end
      end
    end
  end
end
