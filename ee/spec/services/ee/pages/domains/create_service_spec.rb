# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Pages::Domains::CreateService, feature_category: :pages do
  let_it_be(:user) { create(:user) }

  let(:domain) { 'new.domain.com' }
  let(:attributes) { { domain: domain } }
  let(:service) { described_class.new(project, user, attributes) }

  describe 'audit events' do
    let_it_be(:project) { create(:project, :in_subgroup) }

    before_all { project.add_maintainer(user) }

    context 'when licensed' do
      before do
        stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
      end

      context 'when it saves the domain successfully' do
        it 'creates an audit event scoped to the project', :aggregate_failures do
          expect { service.execute }
            .to change { project.pages_domains.count }
            .and change { AuditEventReader.count }.by(1)

          expect(AuditEventReader.last).to have_attributes(
            author: user,
            entity_id: project.id,
            entity_type: 'Project',
            target_details: domain,
            details: include(
              event_name: 'pages_domain_created',
              custom_message: "Created pages domain #{domain}"
            )
          )
        end
      end
    end

    context 'when unlicensed' do
      before do
        stub_licensed_features(admin_audit_log: false, audit_events: false, extended_audit_events: false)
      end

      it 'does not track audit event' do
        expect { service.execute }.not_to change { AuditEventReader.count }
      end
    end
  end
end
