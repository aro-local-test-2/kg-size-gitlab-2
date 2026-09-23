# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::AutoIndexWorker, feature_category: :knowledge_graph do
  let(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker'

  describe '#perform' do
    let_it_be(:top_group) { create(:group) }
    let_it_be(:second_top_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, :nested) }
    let_it_be(:indexed_group) { create(:group) }
    let_it_be(:excluded_group) { create(:group) }
    let_it_be(:user_namespace) { create(:user_namespace) }

    before_all do
      create(:knowledge_graph_enabled_namespace, namespace: indexed_group)
      create(:knowledge_graph_excluded_namespace, namespace: excluded_group)
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_licensed_features(orbit: true)
      stub_ee_application_setting(orbit_auto_index_root_namespace: true)
      allow(Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(true)
    end

    it 'enrolls every missing top-level group' do
      expect { worker.perform }
        .to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(3)

      expect(top_group.reload.knowledge_graph_enabled_namespace).to be_present
      expect(second_top_group.reload.knowledge_graph_enabled_namespace).to be_present
      expect(subgroup.root_ancestor.reload.knowledge_graph_enabled_namespace).to be_present
      expect(indexed_group.reload.knowledge_graph_enabled_namespace).to be_present
      expect(excluded_group.reload.knowledge_graph_enabled_namespace).to be_nil
      expect(user_namespace.reload.knowledge_graph_enabled_namespace).to be_nil
    end

    it 'removes excluded enrollments' do
      Analytics::KnowledgeGraph::EnabledNamespace.insert_all!([{ root_namespace_id: excluded_group.id }])

      expect { worker.perform }
        .to change { excluded_group.reload.knowledge_graph_enabled_namespace }.to(nil)

      worker.perform

      expect(excluded_group.reload.knowledge_graph_enabled_namespace).to be_nil
    end

    it 'is idempotent' do
      worker.perform

      expect { worker.perform }
        .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
    end

    context 'when Knowledge Graph infrastructure is disabled' do
      before do
        stub_feature_flags(knowledge_graph_infra: false)
      end

      it 'does not change enrollments' do
        expect { worker.perform }
          .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
      end
    end

    context 'when the Knowledge Graph service is not configured' do
      before do
        allow(Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(false)
      end

      it 'does not change enrollments' do
        expect { worker.perform }
          .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
      end
    end

    context 'when namespace enrollment is disabled' do
      before do
        stub_feature_flags(orbit_enroll_namespace: false)
      end

      it 'does not change enrollments' do
        expect { worker.perform }
          .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
      end
    end

    context 'when namespace enrollment is enabled for one group' do
      before do
        stub_feature_flags(orbit_enroll_namespace: top_group)
      end

      it 'enrolls only that group' do
        expect { worker.perform }
          .to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)

        expect(Analytics::KnowledgeGraph::EnabledNamespace.for_root_namespace_id(top_group.id)).to exist
        expect(Analytics::KnowledgeGraph::EnabledNamespace.for_root_namespace_id(second_top_group.id)).not_to exist
      end
    end

    context 'when the setting is disabled' do
      before do
        stub_ee_application_setting(orbit_auto_index_root_namespace: false)
      end

      it 'does not enroll missing namespaces' do
        expect { worker.perform }
          .not_to change { top_group.reload.knowledge_graph_enabled_namespace }.from(nil)
      end

      it 'still removes excluded enrollments' do
        Analytics::KnowledgeGraph::EnabledNamespace.insert_all!([{ root_namespace_id: excluded_group.id }])

        expect { worker.perform }
          .to change { excluded_group.reload.knowledge_graph_enabled_namespace }.to(nil)
      end
    end

    context 'when Orbit is unlicensed' do
      before do
        stub_licensed_features(orbit: false)
      end

      it 'does not change enrollments' do
        expect { worker.perform }
          .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
      end
    end

    context 'on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'does not change enrollments' do
        expect { worker.perform }
          .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
      end
    end

    it 'does not remove non-excluded enrollments after the setting is disabled' do
      worker.perform
      count = Analytics::KnowledgeGraph::EnabledNamespace.count
      stub_ee_application_setting(orbit_auto_index_root_namespace: false)

      expect { worker.perform }
        .not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.from(count)
    end
  end
end
