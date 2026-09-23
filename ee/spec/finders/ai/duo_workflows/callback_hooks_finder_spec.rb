# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CallbackHooksFinder, feature_category: :duo_agent_platform do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:project) { create(:project, group: subgroup) }

  let_it_be(:root_group_hook) { create(:group_hook, group: root_group, duo_flow_callback_enabled: true) }
  let_it_be(:subgroup_hook) { create(:group_hook, group: subgroup, duo_flow_callback_enabled: true) }
  let_it_be(:project_hook) { create(:project_hook, project: project, duo_flow_callback_enabled: true) }

  let_it_be(:disabled_group_hook) { create(:group_hook, group: subgroup) }
  let_it_be(:disabled_project_hook) { create(:project_hook, project: project) }

  let_it_be(:sibling_project_hook) do
    create(:project_hook, project: create(:project, group: subgroup), duo_flow_callback_enabled: true)
  end

  let_it_be(:unrelated_group_hook) { create(:group_hook, duo_flow_callback_enabled: true) }

  before do
    stub_licensed_features(group_webhooks: true)
  end

  describe '#execute' do
    subject(:hooks) { described_class.new(container: container).execute }

    context 'when the container is a Project' do
      let(:container) { project }

      it 'returns the project\'s own hooks and those of every ancestor group' do
        expect(hooks).to contain_exactly(project_hook, subgroup_hook, root_group_hook)
      end

      context 'when the project sits in a personal namespace' do
        let_it_be(:personal_project) { create(:project) }
        let_it_be(:personal_project_hook) do
          create(:project_hook, project: personal_project, duo_flow_callback_enabled: true)
        end

        let(:container) { personal_project }

        it 'returns the project hooks instead of raising on the missing group' do
          expect(hooks).to contain_exactly(personal_project_hook)
        end
      end

      context 'when group webhooks are not licensed' do
        before do
          stub_licensed_features(group_webhooks: false)
        end

        it 'drops the ancestor group hooks and keeps the project ones' do
          expect(hooks).to contain_exactly(project_hook)
        end
      end
    end

    context 'when the container is a Group' do
      let(:container) { subgroup }

      it 'returns the group\'s hooks and those of its ancestors, but not descendant project hooks' do
        expect(hooks).to contain_exactly(subgroup_hook, root_group_hook)
      end

      context 'when the group is the root of the hierarchy' do
        let(:container) { root_group }

        it 'does not reach down into descendant groups' do
          expect(hooks).to contain_exactly(root_group_hook)
        end
      end

      context 'when group webhooks are not licensed' do
        before do
          stub_licensed_features(group_webhooks: false)
        end

        it 'returns nothing' do
          expect(hooks).to be_empty
        end
      end
    end

    context 'when the container is neither a Project nor a Group' do
      let(:container) { nil }

      it 'returns nothing' do
        expect(hooks).to be_empty
      end
    end
  end

  describe '#find_by_id' do
    subject(:finder) { described_class.new(container: project) }

    it 'resolves a hook on an ancestor group' do
      expect(finder.find_by_id(root_group_hook.id)).to eq(root_group_hook)
    end

    it 'returns nil for a hook outside the hierarchy' do
      expect(finder.find_by_id(unrelated_group_hook.id)).to be_nil
    end
  end
end
