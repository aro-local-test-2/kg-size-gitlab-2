# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::CreateService, feature_category: :duo_agent_platform do
  include Ai::Catalog::TestHelpers
  include AfterNextHelpers

  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:different_group) { create(:group) }
  let_it_be(:human_user) { create(:user, maintainer_of: project) }
  let_it_be(:composite_identity_enforced) { false }
  let_it_be(:service_account_provisioned_by_group) do
    create(:service_account, developer_of: project, provisioned_by_group: project.group,
      composite_identity_enforced: composite_identity_enforced)
  end

  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let(:current_user) { human_user }
  let(:service_account) { service_account_provisioned_by_group }

  let(:event_types) { [Ai::FlowTrigger::EVENT_TYPES[:mention]] }
  let(:params) do
    { user_id: service_account.id, event_types: event_types, config_path: ".gitlab/duo/flow.yml",
      description: "some flow" }
  end

  let(:service) { described_class.new(project: project, current_user: current_user) }

  before do
    stub_ee_application_setting(duo_features_enabled: true)
    allow(Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
    stub_validate_config_service
  end

  describe '#initialize' do
    it 'rejects a generic authorization bypass' do
      expect do
        described_class.new(
          project: project,
          current_user: current_user,
          authorization_context: :skip_authorization
        )
      end.to raise_error(ArgumentError, 'Invalid inherited foundational-flow authorization context')
    end
  end

  describe '#execute' do
    it 'creates a flow trigger' do
      response = service.execute(params)
      expect(response).to be_success
      flow_trigger = response.payload

      expect(flow_trigger).to be_persisted
      expect(flow_trigger.user).to eq(service_account)
      expect(flow_trigger.event_types).to contain_exactly(Ai::FlowTrigger::EVENT_TYPES[:mention])
      expect(flow_trigger.project).to eq(project)
      expect(service_account.reload.composite_identity_enforced).to be(true)
    end

    it 'does not validate the flow configuration for a config_path trigger' do
      expect(::Ai::Catalog::Items::ValidateConfigService).not_to receive(:new)

      expect(service.execute(params)).to be_success
    end

    it 'emits a flow_trigger_created audit event on success' do
      expect { service.execute(params) }.to change { AuditEventReader.count }.by(1)

      audit_event = AuditEventReader.last
      trigger = Ai::FlowTrigger.last

      expect(audit_event).to have_attributes(
        author: current_user,
        entity_type: 'Project',
        entity_id: project.id,
        target_details: "#{trigger.description} (ID: #{trigger.id})"
      )
      expect(audit_event.details).to include(
        event_name: 'flow_trigger_created',
        target_type: 'Ai::FlowTrigger'
      )
    end

    it 'does not emit an audit event when creation fails' do
      invalid_params = params.merge(event_types: [99])
      expect { service.execute(invalid_params) }.not_to change { AuditEventReader.count }
    end

    it 'does not create a flow schedule for non-scheduled triggers' do
      expect { service.execute(params) }.not_to change { Ai::FlowSchedule.count }
    end

    context 'when the trigger is scheduled with schedule config' do
      let(:event_types) { [Ai::FlowTrigger::EVENT_TYPES[:scheduled]] }
      let(:params) do
        super().merge(filter: { 'scheduled' => { 'frequency' => 'DAILY', 'minute' => 30, 'hour' => 14 } })
      end

      it 'materializes a flow schedule from the filter' do
        response = service.execute(params)

        expect(response).to be_success
        expect(response.payload.flow_schedules.first).to have_attributes(
          cron: '30 14 * * *',
          project_id: project.id,
          active: true
        )
      end

      context 'when the ai_flow_schedules feature flag is disabled' do
        before do
          stub_feature_flags(ai_flow_schedules: false)
        end

        it 'does not materialize a flow schedule' do
          expect { service.execute(params) }.not_to change { Ai::FlowSchedule.count }
        end
      end

      context 'when materializing the flow schedule fails' do
        before do
          allow_next_instance_of(::Ai::FlowSchedules::SyncFromTriggerService) do |sync_service|
            allow(sync_service).to receive(:execute).and_return(ServiceResponse.error(message: 'sync failed'))
          end
        end

        it 'still creates the flow trigger and logs the sync error' do
          expect(service).to receive(:log_error).with(a_string_including('sync failed'))

          response = service.execute(params)

          expect(response).to be_success
          expect(response.payload).to be_persisted
        end
      end
    end

    context 'when ai_catalog_create_third_party_flows is disabled' do
      before do
        stub_feature_flags(ai_catalog_create_third_party_flows: false)
      end

      it 'returns an error' do
        response = service.execute(params)

        expect(response).to be_error
        expect(response.message).to include('You have insufficient permissions')
        expect(response.reason).to eq(:unauthorized)
      end
    end

    context 'when using invalid params' do
      let(:event_types) { [99] }

      it 'returns the error' do
        response = service.execute(params)
        expect(response).not_to be_success
        expect(response.message).to include('invalid event types: 99')
        expect(response.reason).to eq(:validation_error)
      end
    end

    context 'when the current_user is not a maintainer of the project' do
      let(:current_user) { create(:user, developer_of: project) }

      it 'returns an error and does not create the flow trigger' do
        response = service.execute(params)
        expect(response).not_to be_success
        expect(response.reason).to eq(:unauthorized)
      end
    end

    context 'when the provisioning group is not the root ancestor of the project' do
      let(:service_account) { create(:service_account, developer_of: project, provisioned_by_group: different_group) }

      it 'returns an error and does not create the flow trigger' do
        response = service.execute(params)
        expect(response).not_to be_success
      end
    end

    context 'with inherited foundational-flow authorization' do
      let(:inherited_project) { create(:project, :in_group) }
      let(:root_group) { inherited_project.root_ancestor }
      let(:foundational_flow) do
        create(
          :ai_catalog_flow,
          :public,
          :with_released_version,
          organization: root_group.organization,
          foundational_flow_reference: 'developer/v1'
        )
      end

      let(:inherited_service_account) do
        create(:service_account, provisioned_by_group: root_group, composite_identity_enforced: true)
      end

      let(:parent_consumer) do
        create(:ai_catalog_item_consumer, group: root_group, item: foundational_flow,
          service_account: inherited_service_account)
      end

      let(:child_consumer) do
        create(:ai_catalog_item_consumer, project: inherited_project, item: foundational_flow,
          parent_item_consumer: parent_consumer)
      end

      let(:authorization_context) do
        Ai::Catalog::Flows::InheritedProjectAuthorization.new(
          project: inherited_project,
          item: foundational_flow,
          parent_consumer: parent_consumer,
          initiating_user: current_user
        )
      end

      let(:service) do
        described_class.new(
          project: inherited_project,
          current_user: current_user,
          authorization_context: authorization_context
        )
      end

      let(:params) do
        {
          description: "Foundational flow trigger for #{foundational_flow.name}",
          ai_catalog_item_consumer_id: child_consumer.id,
          event_types: foundational_flow.foundational_flow.triggers
        }
      end

      before do
        inherited_project.project_setting.update!(duo_foundational_flows_enabled: true, duo_features_enabled: true)
        create(:ai_catalog_enabled_foundational_flow, :for_project,
          project: inherited_project, catalog_item: foundational_flow)
      end

      it 'rejects a manually supplied service account' do
        response = service.execute(params.merge(user_id: inherited_service_account.id))

        expect(response).to be_error
        expect(response.reason).to eq(:unauthorized)
        expect(child_consumer.reload.flow_trigger).to be_nil
      end

      it 'reloads the project before creating a trigger' do
        other_group = create(:group, organization: root_group.organization)
        authorization_context
        inherited_project.root_ancestor
        Project.where(id: inherited_project.id).update_all(namespace_id: other_group.id)

        expect { service.execute(params) }.not_to change { Ai::FlowTrigger.where(project: inherited_project).count }
      end

      it 'does not validate the flow configuration for a foundational flow' do
        expect(::Ai::Catalog::Items::ValidateConfigService).not_to receive(:new)

        expect(service.execute(params)).to be_success
      end
    end

    context 'when using catalog item configuration' do
      let_it_be(:item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }

      let(:item_consumer_id) { item_consumer.id }

      let(:catalog_params) do
        {
          event_types: event_types,
          description: "catalog flow trigger",
          ai_catalog_item_consumer_id: item_consumer_id
        }
      end

      it 'creates a flow trigger with catalog item' do
        response = service.execute(catalog_params)
        expect(response).to be_success
        flow_trigger = response.payload

        expect(flow_trigger).to be_persisted
        expect(flow_trigger.ai_catalog_item_consumer).to eq(item_consumer)
        expect(flow_trigger.config_path).to be_nil
      end

      context 'when the custom flow configuration is invalid' do
        before do
          allow_next(::Ai::Catalog::Items::ValidateConfigService)
            .to receive(:execute)
            .and_return(ServiceResponse.error(
              message: ['Component missing input variables: goal'],
              reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG
            ))
        end

        it 'returns an error and does not create the flow trigger' do
          expect { service.execute(catalog_params) }.not_to change { Ai::FlowTrigger.count }

          response = service.execute(catalog_params)
          expect(response).to be_error
          expect(response.message)
            .to include('Cannot add trigger events because the custom flow configuration is invalid')
          expect(response.reason).to eq(::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG)
        end

        it 'does not emit an audit event' do
          expect { service.execute(catalog_params) }.not_to change { AuditEventReader.count }
        end
      end

      context 'when Duo Workflow Service is unavailable' do
        before do
          allow_next(::Ai::Catalog::Items::ValidateConfigService)
            .to receive(:execute)
            .and_return(ServiceResponse.error(
              message: 'Unable to validate flow configuration. Duo Workflow Service is currently unavailable.',
              reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE
            ))
        end

        it 'passes through the service-unavailable error and does not create the flow trigger' do
          expect { service.execute(catalog_params) }.not_to change { Ai::FlowTrigger.count }

          response = service.execute(catalog_params)
          expect(response).to be_error
          expect(response.message)
            .to include('Unable to validate flow configuration. Duo Workflow Service is currently unavailable.')
          expect(response.reason).to eq(::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE)
        end
      end

      context 'when the custom flow has no pinned version' do
        before do
          allow_next_found_instance_of(::Ai::Catalog::ItemConsumer) do |consumer|
            allow(consumer).to receive(:pinned_version).and_return(nil)
          end

          allow_next(::Ai::Catalog::Items::ValidateConfigService).to receive(:execute).and_call_original
        end

        it 'returns an error and does not create the flow trigger' do
          expect { service.execute(catalog_params) }.not_to change { Ai::FlowTrigger.count }

          response = service.execute(catalog_params)
          expect(response).to be_error
          expect(response.message)
            .to include('Cannot add trigger events because the custom flow configuration is invalid')
        end
      end

      context 'when ai_catalog_create_third_party_flows is disabled' do
        before do
          stub_feature_flags(ai_catalog_create_third_party_flows: false)
        end

        it 'creates a flow trigger with catalog item' do
          response = service.execute(catalog_params)
          expect(response).to be_success
          flow_trigger = response.payload

          expect(flow_trigger).to be_persisted
          expect(flow_trigger.ai_catalog_item_consumer).to eq(item_consumer)
          expect(flow_trigger.config_path).to be_nil
        end

        context 'when the item consumer does not exist' do
          let(:item_consumer_id) { non_existing_record_id }

          it 'returns an error' do
            response = service.execute(catalog_params)
            expect(response).to be_error
            expect(response.message).to include("Ai catalog item consumer can't be blank")
          end
        end

        context 'when the item consumer is nil' do
          let(:item_consumer_id) { nil }

          it 'returns an error' do
            response = service.execute(catalog_params)
            expect(response).to be_error
            expect(response.message).to include("Ai catalog item consumer can't be blank")
          end
        end
      end

      context 'when also passing a matching user_id' do
        let(:catalog_params) { super().merge(user_id: item_consumer.active_service_account.id) }

        it 'creates a flow trigger with catalog item' do
          response = service.execute(catalog_params)
          expect(response).to be_success
          flow_trigger = response.payload

          expect(flow_trigger).to be_persisted
          expect(flow_trigger.ai_catalog_item_consumer).to eq(item_consumer)
          expect(flow_trigger.user).to be_nil
        end
      end

      context 'when also passing an unrelated user_id' do
        let_it_be(:other_service_account) { create(:service_account, provisioned_by_group: project.group) }

        let(:catalog_params) { super().merge(user_id: other_service_account.id) }

        it 'returns an error' do
          response = service.execute(catalog_params)
          expect(response).to be_error
          expect(response.reason).to eq(:service_account_mismatch)
          expect(response.message).to eq(
            'The service account does not belong to the configuration for the agent or flow ' \
              'associated with this project'
          )
        end
      end
    end

    context 'with invalid catalog item parameters' do
      let_it_be(:other_project) { create(:project, :in_group) }
      let_it_be(:item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: other_project) }

      let(:catalog_params) do
        {
          user_id: service_account.id,
          event_types: event_types,
          description: "catalog flow trigger",
          ai_catalog_item_consumer_id: item_consumer.id
        }
      end

      it 'returns an error' do
        response = service.execute(catalog_params)
        expect(response).to be_error
        expect(response.message).to include('The service account does not belong to the configuration')
      end
    end
  end
end
