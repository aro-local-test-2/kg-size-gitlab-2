# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServers::SetBlockService, feature_category: :ai_catalog_curation do
  let_it_be(:organization) { create(:organization) }
  let_it_be_with_reload(:group) { create(:group, organization: organization) }
  let_it_be(:user) { create(:user) }
  let_it_be(:mcp_server) { create(:ai_catalog_mcp_server, organization: organization) }

  let(:blocked) { true }
  let(:audit_event_class) { AuditEvents::GroupAuditEvent }
  let(:audit_scope_attributes) { { group_id: group.id } }

  subject(:response) do
    described_class.new(container: group, mcp_server: mcp_server, current_user: user, blocked: blocked).execute
  end

  shared_examples 'creates an audit event' do |event_name, verb|
    it 'creates an audit event', :aggregate_failures do
      expect { response }.to change { audit_event_class.count }.by(1)

      audit_event = audit_event_class.last
      expect(audit_event).to have_attributes(
        author_id: user.id,
        target_details: "#{mcp_server.name} (ID: #{mcp_server.id})",
        target_type: 'Ai::Catalog::McpServer',
        event_name: event_name,
        **audit_scope_attributes
      )
      expect(audit_event.details).to include(
        custom_message: "#{verb} MCP server (URL: #{mcp_server.url})"
      )
    end
  end

  shared_examples 'does not create an audit event' do
    it 'does not create an audit event' do
      expect { response }.not_to change { audit_event_class.count }
    end
  end

  before do
    allow(user).to receive(:can?).and_call_original
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?)
      .with(user, :block_ai_catalog_mcp_server, group).and_return(true)
  end

  describe '#execute' do
    context 'when the user is authorized' do
      context 'when blocking' do
        it 'creates a block record and returns success', :aggregate_failures do
          expect { response }.to change { Ai::Catalog::McpServerBlock.count }.by(1)
          expect(response).to be_success
          expect(response.payload[:mcp_server]).to eq(mcp_server)

          block = Ai::Catalog::McpServerBlock.find_by(
            namespace_id: group.id, ai_catalog_mcp_server_id: mcp_server.id
          )
          expect(block).to have_attributes(
            namespace_id: group.id,
            ai_catalog_mcp_server_id: mcp_server.id,
            organization_id: organization.id,
            created_by_id: user.id
          )
        end

        it_behaves_like 'creates an audit event', 'block_ai_catalog_mcp_server', 'Blocked'

        context 'when a block already exists' do
          before do
            create(:ai_catalog_mcp_server_block, namespace: group, mcp_server: mcp_server, organization: organization)
          end

          it 'is idempotent and does not create a duplicate', :aggregate_failures do
            expect { response }.not_to change { Ai::Catalog::McpServerBlock.count }
            expect(response).to be_success
          end

          it_behaves_like 'does not create an audit event'
        end
      end

      context 'when allowing (blocked: false)' do
        let(:blocked) { false }

        context 'when an own block exists' do
          before do
            create(:ai_catalog_mcp_server_block, namespace: group, mcp_server: mcp_server, organization: organization)
          end

          it 'destroys the block', :aggregate_failures do
            expect { response }.to change { Ai::Catalog::McpServerBlock.count }.by(-1)
            expect(response).to be_success
          end

          it_behaves_like 'creates an audit event', 'unblock_ai_catalog_mcp_server', 'Allowed'
        end

        context 'when no block exists at any level' do
          it 'is a no-op and returns success', :aggregate_failures do
            expect { response }.not_to change { Ai::Catalog::McpServerBlock.count }
            expect(response).to be_success
          end

          it_behaves_like 'does not create an audit event'
        end

        context 'when only an ancestor block exists' do
          let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }

          subject(:response) do
            described_class
              .new(container: subgroup, mcp_server: mcp_server, current_user: user, blocked: blocked).execute
          end

          before do
            create(:ai_catalog_mcp_server_block, namespace: group, mcp_server: mcp_server, organization: organization)
            allow(Ability).to receive(:allowed?)
              .with(user, :block_ai_catalog_mcp_server, subgroup).and_return(true)
          end

          it 'is a no-op that keeps the ancestor block and returns success', :aggregate_failures do
            expect { response }.not_to change { Ai::Catalog::McpServerBlock.count }
            expect(response).to be_success
            expect(Ai::Catalog::McpServerBlock.exists?(namespace_id: group.id)).to be(true)
          end

          it_behaves_like 'does not create an audit event'
        end
      end
    end

    context 'when the user is not authorized' do
      before do
        allow(Ability).to receive(:allowed?)
          .with(user, :block_ai_catalog_mcp_server, group).and_return(false)
      end

      it 'returns an error and does not change records', :aggregate_failures do
        expect { response }.not_to change { Ai::Catalog::McpServerBlock.count }
        expect(response).to be_error
        expect(response.message).to include('You have insufficient permissions')
      end

      it_behaves_like 'does not create an audit event'
    end

    context 'when the MCP server belongs to a different organization' do
      let_it_be(:mcp_server) { create(:ai_catalog_mcp_server, organization: create(:organization)) }

      it 'returns an error', :aggregate_failures do
        expect(response).to be_error
        expect(response.message).to include('MCP server does not belong to this organization')
      end

      it_behaves_like 'does not create an audit event'
    end

    context 'with a project container' do
      let_it_be_with_reload(:project) { create(:project, group: group, organization: organization) }

      let(:audit_event_class) { AuditEvents::ProjectAuditEvent }
      let(:audit_scope_attributes) { { project_id: project.id } }

      subject(:response) do
        described_class.new(container: project, mcp_server: mcp_server, current_user: user, blocked: blocked).execute
      end

      before do
        allow(Ability).to receive(:allowed?)
          .with(user, :block_ai_catalog_mcp_server, project).and_return(true)
      end

      it 'stores the block against the project namespace', :aggregate_failures do
        expect { response }.to change { Ai::Catalog::McpServerBlock.count }.by(1)
        expect(response).to be_success

        block = Ai::Catalog::McpServerBlock.find_by(
          namespace_id: project.project_namespace_id, ai_catalog_mcp_server_id: mcp_server.id
        )
        expect(block).to be_present
      end

      # The block row is keyed on the project namespace, but the audit event belongs to the
      # project itself so it shows up in the project audit log.
      it_behaves_like 'creates an audit event', 'block_ai_catalog_mcp_server', 'Blocked'

      context 'when allowing (blocked: false)' do
        let(:blocked) { false }

        before do
          create(:ai_catalog_mcp_server_block,
            namespace: project.project_namespace, mcp_server: mcp_server, organization: organization)
        end

        it 'destroys the project-namespace block' do
          expect { response }.to change { Ai::Catalog::McpServerBlock.count }.by(-1)
        end

        it_behaves_like 'creates an audit event', 'unblock_ai_catalog_mcp_server', 'Allowed'
      end
    end
  end
end
