# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::SyncProjectFoundationalFlowsWorker, feature_category: :ai_abstraction_layer do
  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, group: group, creator: user) }

  subject(:worker) { described_class.new }

  def expect_inherited_flow_materialized(project, item, service_account, user_id)
    expect { worker.perform(project.id, user_id) }
      .to change { Ai::Catalog::ItemConsumer.where(project: project, item: item).count }.by(1)
      .and change { project.members.where(user: service_account).count }.by(1)
      .and change { project.ai_flow_triggers.count }.by(1)
  end

  describe '#perform' do
    let(:sync_service) { instance_double(Ai::Catalog::Flows::SyncFoundationalFlowsService) }

    before do
      allow(Ai::Catalog::Flows::SyncFoundationalFlowsService).to receive(:new).and_return(sync_service)
      allow(sync_service).to receive(:execute)
    end

    context 'when project does not exist' do
      it 'returns early without error' do
        expect(Ai::Catalog::Flows::SyncFoundationalFlowsService).not_to receive(:new)

        expect { worker.perform(non_existing_record_id, user.id) }.not_to raise_error
      end
    end

    context 'when project has no group' do
      let_it_be(:personal_project) { create(:project, :in_user_namespace) }

      it 'returns early without syncing' do
        expect(Ai::Catalog::Flows::SyncFoundationalFlowsService).not_to receive(:new)

        worker.perform(personal_project.id, user.id)
      end
    end

    context 'when duo_foundational_flows_enabled is false' do
      before do
        project.project_setting.update!(duo_foundational_flows_enabled: false)
      end

      it 'returns early without syncing' do
        expect(Ai::Catalog::Flows::SyncFoundationalFlowsService).not_to receive(:new)

        worker.perform(project.id, user.id)
      end
    end

    context 'when duo_foundational_flows_enabled is true' do
      before do
        project.project_setting.update!(duo_foundational_flows_enabled: true)
        group.namespace_settings.update!(duo_foundational_flows_enabled: true)
      end

      it 'syncs foundational flows and calls service' do
        expect(Ai::Catalog::Flows::SyncFoundationalFlowsService).to receive(:new)
          .with(project, current_user: user, provisioning_mode: :inherited_project, initiating_user_id: user.id)
          .and_return(sync_service)
        expect(sync_service).to receive(:execute)

        worker.perform(project.id, user.id)
      end

      context 'when user_id is nil' do
        it 'calls service with nil user' do
          expect(Ai::Catalog::Flows::SyncFoundationalFlowsService).to receive(:new)
            .with(project, current_user: nil, provisioning_mode: :inherited_project, initiating_user_id: nil)
            .and_return(sync_service)
          expect(sync_service).to receive(:execute)

          worker.perform(project.id, nil)
        end
      end

      context 'when user does not exist' do
        it 'calls service with nil user' do
          expect(Ai::Catalog::Flows::SyncFoundationalFlowsService).to receive(:new)
            .with(project, current_user: nil, provisioning_mode: :inherited_project,
              initiating_user_id: non_existing_record_id)
            .and_return(sync_service)
          expect(sync_service).to receive(:execute)

          worker.perform(project.id, non_existing_record_id)
        end
      end

      context 'with persisted inherited flow state' do
        let(:flow) do
          create(
            :ai_catalog_flow,
            :public,
            :with_released_version,
            organization: group.organization,
            foundational_flow_reference: 'developer/v1'
          )
        end

        let(:service_account) do
          create(:service_account, provisioned_by_group: group, composite_identity_enforced: true)
        end

        let!(:parent_consumer) do
          create(:ai_catalog_item_consumer, group: group, item: flow, service_account: service_account)
        end

        before_all do
          group.add_developer(user)
        end

        before do
          allow(Ai::Catalog::Flows::SyncFoundationalFlowsService).to receive(:new).and_call_original
          group.namespace_settings.update!(duo_features_enabled: true)
          project.project_setting.update!(duo_features_enabled: true)
          create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: group, catalog_item: flow)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
        end

        it 'materializes inherited state for a Developer initiator' do
          expect(Ability.allowed?(user, :provision_ai_catalog, project)).to be(false)

          expect_inherited_flow_materialized(project, flow, service_account, user.id)
        end

        it 'materializes inherited state with a nil initiator' do
          expect_inherited_flow_materialized(project, flow, service_account, nil)
        end

        it 'retains the original initiator ID after the user has been deleted' do
          deleted_user_id = non_existing_record_id

          expect_inherited_flow_materialized(project, flow, service_account, deleted_user_id)

          audit_event = AuditEvents::ProjectAuditEvent.all.find do |event|
            event.details[:event_name] == 'enable_ai_catalog_flow' && event.project_id == project.id
          end

          expect(audit_event.details).to include(
            author_name: '(System)',
            provisioning_source: 'inherited_project',
            initiating_user_id: deleted_user_id
          )
        end
      end

      context 'with six eligible inherited flows' do
        let(:flow_references) do
          %w[
            code_review/v1
            sast_fp_detection/v1
            resolve_sast_vulnerability/v1
            developer/v1
            fix_pipeline/v1
            convert_to_gl_ci/v1
          ]
        end

        let!(:flows) do
          flow_references.map do |reference|
            create(
              :ai_catalog_flow,
              :public,
              :with_released_version,
              organization: group.organization,
              foundational_flow_reference: reference
            )
          end
        end

        before do
          allow(Ai::Catalog::Flows::SyncFoundationalFlowsService).to receive(:new).and_call_original
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
          stub_licensed_features(ai_features: true)

          group.namespace_settings.update!(duo_features_enabled: true)
          project.project_setting.update!(duo_features_enabled: true)

          flows.each do |flow|
            service_account = create(
              :service_account,
              provisioned_by_group: group,
              composite_identity_enforced: true
            )
            create(:ai_catalog_item_consumer, group: group, item: flow, service_account: service_account)
            create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: group, catalog_item: flow)
          end
        end

        it 'bounds the total query count for the complete worker path', :aggregate_failures do
          recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
            worker.perform(project.id, user.id)
          end

          expect(Ai::Catalog::ItemConsumer.where(project: project, item: flows).count).to eq(6)
          # This fixture performs six consumer writes and one trigger write. The ceiling leaves 17 queries of
          # headroom above the isolated measurement of 473 for suite-state variance.
          expect(recorder).not_to exceed_all_query_limit(490)
        end
      end
    end
  end

  describe 'worker attributes' do
    it 'has the correct feature category' do
      expect(described_class.get_feature_category).to eq(:ai_abstraction_layer)
    end

    it 'has the correct urgency' do
      expect(described_class.get_urgency).to eq(:low)
    end

    it 'is idempotent' do
      expect(described_class.idempotent?).to be(true)
    end

    it 'does not have external dependencies' do
      expect(described_class.worker_has_external_dependencies?).to be(false)
    end
  end
end
