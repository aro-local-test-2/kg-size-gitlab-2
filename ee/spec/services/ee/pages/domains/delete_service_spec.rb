# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Pages::Domains::DeleteService, feature_category: :pages do
  let_it_be(:user) { create(:user) }
  let_it_be(:pages_domain) { create(:pages_domain) }

  subject(:service) { described_class.new(pages_domain.project, user, nil) }

  describe 'audit events' do
    before_all { pages_domain.project.add_maintainer(user) }

    context 'when licensed' do
      before do
        stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
      end

      context 'when it deletes the domain successfully' do
        it 'creates an audit event scoped to the project', :aggregate_failures do
          expect { service.execute(pages_domain) }
            .to change { pages_domain.project.pages_domains.count }
            .and change { AuditEventReader.count }.by(1)

          expect(AuditEventReader.last).to have_attributes(
            author: user,
            entity_id: pages_domain.project.id,
            entity_type: 'Project',
            target_details: pages_domain.domain,
            details: include(
              event_name: 'pages_domain_deleted',
              custom_message: "Deleted pages domain #{pages_domain.domain}"
            )
          )
        end
      end

      context 'when the domain fails to be destroyed' do
        before do
          allow(pages_domain).to receive(:destroy).and_return(false)
        end

        it 'does not track audit event' do
          expect { service.execute(pages_domain) }.not_to change { AuditEventReader.count }
        end
      end
    end

    context 'when unlicensed' do
      before do
        stub_licensed_features(admin_audit_log: false, audit_events: false, extended_audit_events: false)
      end

      it 'does not track audit event' do
        expect { service.execute(pages_domain) }.not_to change { AuditEventReader.count }
      end
    end
  end
end
