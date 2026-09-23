# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DuoChatPanel::Container, :aggregate_failures, feature_category: :duo_chat do
  let(:user) { build_stubbed(:user) }
  let(:project) { nil }
  let(:group) { nil }
  let(:controller_name) { nil }

  subject(:container) do
    described_class.new(project: project, group: group, user: user, controller_name: controller_name)
  end

  before do
    allow(::Gitlab::Llm::DuoChat).to receive(:duo_scope_hash)
      .with(user, project, group, controller_name)
      .and_return(duo_scope)
  end

  context 'when duo_scope resolves to a project' do
    let(:project) { build_stubbed(:project) }
    let(:duo_scope) { { project: project, namespace: nil, default_namespace_applied: false } }

    it 'returns project type' do
      expect(container.type).to eq('project')
      expect(container.project?).to be(true)
    end

    describe '#record' do
      it { is_expected.to have_attributes(record: project) }
    end

    describe '#source' do
      it { is_expected.to have_attributes(source: project) }
    end

    it 'delegates to the record' do
      expect(container.to_global_id).to eq(project.to_global_id)
      expect(container.root_ancestor).to eq(project.root_ancestor)
      expect(container.persisted?).to eq(project.persisted?)
    end

    it 'returns the correct admin permission' do
      expect(container.admin_permission).to eq(:admin_project)
    end

    it 'returns project_id and no namespace_id' do
      expect(container.project_id).to eq(project.to_global_id.to_s)
      expect(container.namespace_id).to be_nil
    end

    it 'returns the project_path' do
      expect(container.project_path).to eq(project.full_path)
    end

    it 'returns the record from #project and nil from #group' do
      expect(container.project).to eq(project)
      expect(container.group).to be_nil
    end

    it 'returns the root_namespace_id' do
      expect(container.root_namespace_id).to eq(project.root_ancestor.to_global_id.to_s)
    end

    it 'returns default_namespace_applied?' do
      expect(container.default_namespace_applied?).to be(false)
    end

    describe '#user_can_admin?' do
      it 'checks admin_project permission' do
        allow(user).to receive(:can?).with(:admin_project, project).and_return(true)

        expect(container.user_can_admin?(user)).to be(true)
      end

      it 'returns false when user lacks permission' do
        allow(user).to receive(:can?).with(:admin_project, project).and_return(false)

        expect(container.user_can_admin?(user)).to be(false)
      end
    end

    describe '#duo_settings_path' do
      it 'returns the project edit path' do
        expected_path = ::Gitlab::Routing.url_helpers.edit_project_path(
          project, anchor: 'js-gitlab-duo-settings'
        )

        expect(container.duo_settings_path).to eq(expected_path)
      end
    end

    describe '#admin_duo_settings_path' do
      it 'returns the project settings anchor for an administrator' do
        allow(user).to receive(:can?).with(:admin_project, project).and_return(true)

        expect(container.admin_duo_settings_path(user)).to eq(container.duo_settings_path)
      end

      it 'returns nil when the user cannot administer the project' do
        allow(user).to receive(:can?).with(:admin_project, project).and_return(false)

        expect(container.admin_duo_settings_path(user)).to be_nil
      end
    end
  end

  context 'when duo_scope resolves to a group' do
    let(:group) { build_stubbed(:group) }
    let(:duo_scope) { { project: nil, namespace: group, default_namespace_applied: false } }

    it 'returns group type' do
      expect(container.type).to eq('group')
      expect(container.project?).to be(false)
    end

    describe '#record' do
      it { is_expected.to have_attributes(record: group) }
    end

    describe '#source' do
      it { is_expected.to have_attributes(source: group) }
    end

    it 'returns the correct admin permission' do
      expect(container.admin_permission).to eq(:admin_group)
    end

    it 'returns namespace_id and no project_id' do
      expect(container.namespace_id).to eq(group.to_global_id.to_s)
      expect(container.project_id).to be_nil
    end

    it 'returns nil for project_path' do
      expect(container.project_path).to be_nil
    end

    it 'returns the record from #group and nil from #project' do
      expect(container.group).to eq(group)
      expect(container.project).to be_nil
    end

    describe '#user_can_admin?' do
      it 'checks admin_group permission' do
        allow(user).to receive(:can?).with(:admin_group, group).and_return(true)

        expect(container.user_can_admin?(user)).to be(true)
      end
    end

    describe '#duo_settings_path' do
      it 'delegates to the group record' do
        allow(group).to receive(:duo_settings_path).and_return('/group/duo-settings')

        expect(container.duo_settings_path).to eq('/group/duo-settings')
      end
    end

    describe '#admin_duo_settings_path' do
      before do
        allow(group).to receive(:duo_settings_path).and_return('/group/duo-settings')
      end

      it 'delegates to the group for an administrator' do
        allow(user).to receive(:can?).with(:admin_group, group).and_return(true)

        expect(container.admin_duo_settings_path(user)).to eq('/group/duo-settings')
      end

      it 'returns nil when the user cannot administer the group' do
        allow(user).to receive(:can?).with(:admin_group, group).and_return(false)

        expect(container.admin_duo_settings_path(user)).to be_nil
      end
    end
  end

  context 'when duo_scope falls back to the default Duo namespace' do
    let(:group) { build_stubbed(:group) }
    let(:duo_scope) { { project: nil, namespace: group, default_namespace_applied: true } }

    describe '#admin_duo_settings_path' do
      it 'returns nil so the current page does not link to an unrelated container' do
        expect(user).not_to receive(:can?)

        expect(container.admin_duo_settings_path(user)).to be_nil
      end
    end
  end

  context 'when duo_scope resolves to a user namespace' do
    let(:user_namespace) { build_stubbed(:user_namespace) }
    let(:duo_scope) { { project: nil, namespace: user_namespace, default_namespace_applied: false } }

    describe '#admin_duo_settings_path' do
      it 'returns nil because only groups have Duo settings' do
        allow(user).to receive(:can?).with(:admin_group, user_namespace).and_return(true)

        expect(container.admin_duo_settings_path(user)).to be_nil
      end
    end
  end

  context 'when duo_scope resolves to nil (no container)' do
    let(:duo_scope) { { project: nil, namespace: nil, default_namespace_applied: true } }

    it 'returns group type by default' do
      expect(container.type).to eq('group')
      expect(container.project?).to be(false)
    end

    describe '#record' do
      it { is_expected.to have_attributes(record: nil) }
    end

    describe '#source' do
      it { is_expected.to have_attributes(source: nil) }
    end

    it { is_expected.not_to be_persisted }

    it 'returns nil for delegated methods' do
      expect(container.to_global_id).to be_nil
      expect(container.root_ancestor).to be_nil
      expect(container.duo_features_enabled).to be_nil
    end

    it 'returns nil for project_id and namespace_id' do
      expect(container.project_id).to be_nil
      expect(container.namespace_id).to be_nil
    end

    it 'returns nil for root_namespace_id' do
      expect(container.root_namespace_id).to be_nil
    end

    it 'returns default_namespace_applied?' do
      expect(container.default_namespace_applied?).to be(true)
    end

    it 'returns nil for #project and #group' do
      expect(container.project).to be_nil
      expect(container.group).to be_nil
    end

    describe '#admin_duo_settings_path' do
      it 'returns nil without checking permissions' do
        expect(user).not_to receive(:can?)

        expect(container.admin_duo_settings_path(user)).to be_nil
      end
    end
  end

  context 'when the project is not persisted' do
    let(:project) { build(:project) }
    let(:duo_scope) { { project: project, namespace: nil, default_namespace_applied: false } }

    it 'returns nil for #project despite project? being true' do
      expect(container.project?).to be(true)
      expect(container.persisted?).to be(false)
      expect(container.project).to be_nil
    end

    describe '#admin_duo_settings_path' do
      it 'returns nil' do
        expect(container.admin_duo_settings_path(user)).to be_nil
      end
    end
  end

  context 'when the group is not persisted' do
    let(:group) { build(:group) }
    let(:duo_scope) { { project: nil, namespace: group, default_namespace_applied: false } }

    it 'returns nil for #group despite project? being false' do
      expect(container.project?).to be(false)
      expect(container.persisted?).to be(false)
      expect(container.group).to be_nil
    end
  end

  describe 'memoization' do
    let(:project) { build_stubbed(:project) }
    let(:duo_scope) { { project: project, namespace: nil, default_namespace_applied: false } }

    it 'only resolves duo_scope_hash once across multiple calls' do
      container.record
      container.type
      container.persisted?
      container.project_id

      expect(::Gitlab::Llm::DuoChat).to have_received(:duo_scope_hash).once
    end
  end
end
