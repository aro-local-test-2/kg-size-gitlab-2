# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Pages::Domains::UpdateService, feature_category: :pages do
  let_it_be(:user) { create(:user) }

  let(:params) do
    attributes_for(:pages_domain, :with_trusted_chain).slice(:key, :certificate).tap do |params|
      params[:user_provided_key] = params.delete(:key)
      params[:user_provided_certificate] = params.delete(:certificate)
    end
  end

  let(:service) { described_class.new(pages_domain.project, user, params) }

  describe 'audit events' do
    let_it_be(:project) { create(:project, :in_subgroup) }
    let(:pages_domain) { create(:pages_domain, project: project) }

    before_all { project.add_maintainer(user) }

    context 'when licensed' do
      before do
        stub_licensed_features(admin_audit_log: true, audit_events: true, extended_audit_events: true)
      end

      context 'when it updates the domain successfully' do
        it 'creates an audit event scoped to the project', :aggregate_failures do
          expect { service.execute(pages_domain) }
            .to change { AuditEventReader.count }.by(1)

          expect(AuditEventReader.last).to have_attributes(
            author: user,
            entity_id: project.id,
            entity_type: 'Project',
            target_details: pages_domain.domain,
            details: include(
              event_name: 'pages_domain_updated',
              custom_message: "Updated pages domain #{pages_domain.domain}"
            )
          )
        end
      end

      context 'when it fails to update the domain' do
        let(:params) { { user_provided_certificate: nil } }

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
