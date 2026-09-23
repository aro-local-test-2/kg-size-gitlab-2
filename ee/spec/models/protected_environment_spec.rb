# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProtectedEnvironment, feature_category: :continuous_delivery do
  describe 'associations' do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:deploy_access_levels) }
    it { is_expected.to have_many(:approval_rules).class_name('ProtectedEnvironments::ApprovalRule').inverse_of(:protected_environment) }
  end

  describe 'validation' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:deploy_access_levels) }

    it do
      is_expected.to validate_numericality_of(:required_approval_count)
                       .only_integer
                       .is_greater_than_or_equal_to(0)
                       .is_less_than_or_equal_to(5)
    end

    it 'can not belong to both group and project' do
      group = build(:group)
      project = build(:project)
      protected_environment = build(:protected_environment, :maintainers_can_deploy, group: group, project: project)

      expect { protected_environment.save! }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation/)
    end

    it 'must belong to one of group or project' do
      protected_environment = build(:protected_environment, :maintainers_can_deploy, group: nil, project: nil)

      expect { protected_environment.save! }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation/)
    end

    context 'group-level protected environment' do
      let_it_be(:group) { create(:group) }

      it 'passes the validation when the name is listed in the tiers' do
        protection = build(:protected_environment, :maintainers_can_deploy, name: 'production', group: group)

        expect(protection).to be_valid
      end

      it 'fails the validation when the name is not listed in the tiers' do
        protection = build(:protected_environment, name: 'customer-portal', group: group)

        expect(protection).not_to be_valid
        expect(protection.errors[:name].first).to include('must be one of environment tiers')
      end
    end
  end

  describe '#accessible_to?' do
    let_it_be(:project) { create(:project) }
    let_it_be(:environment) { create(:environment, project: project) }
    let_it_be_with_reload(:protected_environment) do
      create(:protected_environment, name: environment.name, project: project)
    end

    let_it_be_with_reload(:user) { create(:user) }

    subject { protected_environment.accessible_to?(user) }

    context 'when user is admin' do
      let(:user) { create(:user, :admin) }

      it { is_expected.to be_truthy }
    end

    context 'when access has been granted to user' do
      before do
        create_deploy_access_level(protected_environment, user: user)
      end

      it { is_expected.to be_truthy }
    end

    context 'when specific access has been assigned to a group' do
      let(:group) { create(:group) }

      before do
        create_deploy_access_level(protected_environment, group: group)
      end

      it 'allows members of the group' do
        group.add_developer(user)

        expect(subject).to be_truthy
      end

      it 'rejects non-members of the group' do
        expect(subject).to be_falsy
      end
    end

    context 'when access has been granted to maintainers' do
      before do
        create_deploy_access_level(protected_environment, access_level: Gitlab::Access::MAINTAINER)
      end

      it 'allows maintainers' do
        project.add_maintainer(user)

        expect(subject).to be_truthy
      end

      it 'rejects developers' do
        project.add_developer(user)

        expect(subject).to be_falsy
      end
    end

    context 'when access has been granted to developers' do
      before do
        create_deploy_access_level(protected_environment, access_level: Gitlab::Access::DEVELOPER)
      end

      it 'allows maintainers' do
        project.add_maintainer(user)

        expect(subject).to be_truthy
      end

      it 'allows developers' do
        project.add_developer(user)

        expect(subject).to be_truthy
      end
    end
  end

  describe '#container_access_level' do
    subject { protected_environment.container_access_level(user) }

    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:maintainer) { create(:user) }
    let_it_be(:developer) { create(:user) }

    before_all do
      project.add_maintainer(maintainer)
      project.add_developer(developer)
      group.add_maintainer(maintainer)
      group.add_developer(developer)
    end

    shared_examples_for 'correct access levels' do
      context 'for project maintainer' do
        let(:user) { maintainer }

        it { is_expected.to eq(Gitlab::Access::MAINTAINER) }
      end

      context 'for project developer' do
        let(:user) { developer }

        it { is_expected.to eq(Gitlab::Access::DEVELOPER) }
      end

      context 'when user is nil' do
        let(:user) { nil }

        it { is_expected.to eq(Gitlab::Access::NO_ACCESS) }
      end
    end

    context 'with project-level protected environment' do
      let_it_be(:protected_environment) do
        create(:protected_environment, :project_level, project: project)
      end

      it_behaves_like 'correct access levels'
    end

    context 'with group-level protected environment' do
      let_it_be(:protected_environment) do
        create(:protected_environment, :group_level, group: group)
      end

      it_behaves_like 'correct access levels'
    end
  end

  describe '#project_level?' do
    subject { protected_environment.project_level? }

    context 'for a project-level protected environment' do
      let_it_be(:protected_environment) { create(:protected_environment, :project_level) }

      it { is_expected.to be_truthy }
    end

    context 'for a group-level protected environment' do
      let_it_be(:protected_environment) { create(:protected_environment, :group_level) }

      it { is_expected.to be_falsey }
    end
  end

  describe '#group_level?' do
    subject { protected_environment.group_level? }

    context 'for a group-level protected environment' do
      let_it_be(:protected_environment) { create(:protected_environment, :group_level) }

      it { is_expected.to be_truthy }
    end

    context 'for a project-level protected environment' do
      let_it_be(:protected_environment) { create(:protected_environment, :project_level) }

      it { is_expected.to be_falsey }
    end
  end

  describe '.sorted_by_name' do
    subject(:protected_environments) { described_class.sorted_by_name }

    it "sorts protected environments by name" do
      %w[staging production development].each { |name| create(:protected_environment, name: name) }

      expect(protected_environments.map(&:name)).to eq %w[development production staging]
    end
  end

  describe '.with_environment_id' do
    subject(:protected_environments) { described_class.with_environment_id }

    it "sets corresponding environment id if there is environment matching by name and project" do
      project = create(:project)
      environment = create(:environment, project: project, name: 'production')

      production = create(:protected_environment, project: project, name: 'production')
      removed_environment = create(:protected_environment, project: project, name: 'removed environment')

      expect(protected_environments).to match_array [production, removed_environment]
      expect(protected_environments.find { |e| e.name == 'production' }.environment_id).to eq environment.id
      expect(protected_environments.find { |e| e.name == 'removed environment' }.environment_id).to be_nil
    end
  end

  describe '.revoke_user' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project) }
    let_it_be_with_reload(:protected_environment) do
      create(:protected_environment, project: project, name: 'production')
    end

    let(:deploy_access_level_for_user) { create_deploy_access_level(protected_environment, user: user) }

    before_all do
      create_deploy_access_level(protected_environment, user: create(:user))
      create_deploy_access_level(protected_environment, group: create(:group))
    end

    it 'deletes matching deploy access levels for the given user' do
      expect(protected_environment.deploy_access_levels).to include(deploy_access_level_for_user)

      project.protected_environments.revoke_user(user)

      protected_environment.reload
      expect(protected_environment.deploy_access_levels).not_to include(deploy_access_level_for_user)
    end

    context 'when the user is the sole approver on the protected environment' do
      it 'preserves the approval rule but still deletes the deploy access level', :aggregate_failures do
        stub_licensed_features(protected_environments: true)
        create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
        environment = create(:environment, project: project, name: protected_environment.name)
        deploy_access_level_for_user

        expect { project.protected_environments.revoke_user(user) }
          .not_to change { ProtectedEnvironments::ApprovalRule.count }

        expect(environment.required_approval_count).to be > 0
        expect(environment.has_approval_rules?).to be(true)

        protected_environment.reload
        expect(protected_environment.deploy_access_levels).not_to include(deploy_access_level_for_user)
      end
    end

    context 'when other approvers remain on the protected environment' do
      it 'deletes the user approval rule' do
        user_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: user)
        create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: create(:user))

        expect { project.protected_environments.revoke_user(user) }
          .to change { ProtectedEnvironments::ApprovalRule.exists?(user_rule.id) }.from(true).to(false)
      end
    end

    context 'when user is assigned to protected environment in the other project' do
      let(:other_project) { create(:project) }
      let(:other_protected_environment) { create(:protected_environment, project: other_project, name: 'production') }
      let(:other_deploy_access_level_for_user) { create_deploy_access_level(other_protected_environment, user: user) }

      it 'deletes matching deploy access levels for the given user in the specific project' do
        expect(protected_environment.deploy_access_levels).to include(deploy_access_level_for_user)
        expect(other_protected_environment.deploy_access_levels).to include(other_deploy_access_level_for_user)

        project.protected_environments.revoke_user(user)
        other_project.protected_environments.revoke_user(user)

        protected_environment.reload
        other_protected_environment.reload
        expect(protected_environment.deploy_access_levels).not_to include(deploy_access_level_for_user)
        expect(other_protected_environment.deploy_access_levels).not_to include(other_deploy_access_level_for_user)
      end
    end

    context 'when the remaining approver is role-based' do
      it 'still deletes the user approval rule' do
        user_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: user)
        create(:protected_environment_approval_rule,
          protected_environment: protected_environment, access_level: Gitlab::Access::MAINTAINER)

        expect { project.protected_environments.revoke_user(user) }
          .to change { ProtectedEnvironments::ApprovalRule.exists?(user_rule.id) }.from(true).to(false)
      end
    end

    context 'when the remaining approver is group-based' do
      it 'still deletes the user approval rule' do
        user_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: user)
        create(:protected_environment_approval_rule,
          protected_environment: protected_environment, group: create(:group))

        expect { project.protected_environments.revoke_user(user) }
          .to change { ProtectedEnvironments::ApprovalRule.exists?(user_rule.id) }.from(true).to(false)
      end
    end

    context 'when the project has multiple protected environments with different outcomes' do
      it 'preserves the sole-approver rule and deletes the redundant one', :aggregate_failures do
        other_environment = create(:protected_environment, project: project, name: 'staging')

        sole_approver_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: user)
        redundant_rule = create(:protected_environment_approval_rule,
          protected_environment: other_environment, user: user)
        create(:protected_environment_approval_rule,
          protected_environment: other_environment, user: create(:user))

        project.protected_environments.revoke_user(user)

        expect(ProtectedEnvironments::ApprovalRule.exists?(sole_approver_rule.id)).to be(true)
        expect(ProtectedEnvironments::ApprovalRule.exists?(redundant_rule.id)).to be(false)
      end
    end

    context 'when called unscoped on the class' do
      it 'raises instead of locking every protected environment in the instance' do
        expect { described_class.revoke_user(user) }.to raise_error(ArgumentError)
      end
    end

    context 'when called with a scope that does not constrain project_id' do
      it 'raises instead of locking every protected environment matching an unrelated attribute' do
        expect { described_class.where(name: 'production').revoke_user(user) }.to raise_error(ArgumentError)
      end
    end

    context 'when called with a scope naming multiple projects' do
      it 'raises instead of locking and deleting across every named project' do
        expect { described_class.where(project_id: [project.id, create(:project).id]).revoke_user(user) }
          .to raise_error(ArgumentError)
      end
    end

    context 'when called with a scope of project_id: nil' do
      it 'raises instead of matching every group-level environment in the instance' do
        expect { described_class.where(project_id: nil).revoke_user(user) }.to raise_error(ArgumentError)
      end
    end

    context 'when called with a subquery scope' do
      it 'raises, since where_values_hash cannot distinguish this from project_id: nil' do
        expect { described_class.where(project_id: Project.where(id: project.id)).revoke_user(user) }
          .to raise_error(ArgumentError)
      end
    end

    it 'locks the approval rule rows, not the parent protected_environment row' do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
      create(:protected_environment_approval_rule,
        protected_environment: protected_environment, user: create(:user))

      recorder = ActiveRecord::QueryRecorder.new { project.protected_environments.revoke_user(user) }

      expect(recorder.log).to include(a_string_matching(/SELECT.*"protected_environment_approval_rules".*FOR UPDATE/))
      expect(recorder.log).not_to include(a_string_matching(/SELECT.*"protected_environments".*FOR UPDATE/))
    end
  end

  describe '.revoke_group' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project) }
    let_it_be_with_reload(:protected_environment) do
      create(:protected_environment, project: project, name: 'production')
    end

    let(:deploy_access_level_for_group) { create_deploy_access_level(protected_environment, group: group) }

    it 'deletes matching deploy access levels for the given group' do
      _deploy_access_level_for_different_group = create_deploy_access_level(protected_environment,
        group: create(:group))
      _deploy_access_level_for_user = create_deploy_access_level(protected_environment, user: create(:user))

      expect(protected_environment.deploy_access_levels).to include(deploy_access_level_for_group)

      project.protected_environments.revoke_group(group)

      protected_environment.reload
      expect(protected_environment.deploy_access_levels).not_to include(deploy_access_level_for_group)
    end

    context 'when the group is the sole approver on the protected environment' do
      it 'preserves the approval rule but still deletes the deploy access level', :aggregate_failures do
        stub_licensed_features(protected_environments: true)
        create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
        environment = create(:environment, project: project, name: protected_environment.name)
        deploy_access_level_for_group

        expect { project.protected_environments.revoke_group(group) }
          .not_to change { ProtectedEnvironments::ApprovalRule.count }

        expect(environment.required_approval_count).to be > 0
        expect(environment.has_approval_rules?).to be(true)

        protected_environment.reload
        expect(protected_environment.deploy_access_levels).not_to include(deploy_access_level_for_group)
      end
    end

    context 'when other approvers remain on the protected environment' do
      it 'deletes the group approval rule' do
        group_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, group: group)
        create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: create(:user))

        expect { project.protected_environments.revoke_group(group) }
          .to change { ProtectedEnvironments::ApprovalRule.exists?(group_rule.id) }.from(true).to(false)
      end
    end

    context 'when user is assigned to protected environment in the other project' do
      let(:other_project) { create(:project) }
      let(:other_protected_environment) { create(:protected_environment, project: other_project, name: 'production') }
      let(:other_deploy_access_level_for_group) do
        create_deploy_access_level(other_protected_environment, group: group)
      end

      it 'returns matching deploy access levels for the given group in the specific project' do
        expect(protected_environment.deploy_access_levels).to include(deploy_access_level_for_group)
        expect(other_protected_environment.deploy_access_levels).to include(other_deploy_access_level_for_group)

        project.protected_environments.revoke_group(group)
        other_project.protected_environments.revoke_group(group)

        protected_environment.reload
        other_protected_environment.reload
        expect(protected_environment.deploy_access_levels).not_to include(deploy_access_level_for_group)
        expect(other_protected_environment.deploy_access_levels).not_to include(other_deploy_access_level_for_group)
      end
    end

    context 'when the remaining approver is role-based' do
      it 'still deletes the group approval rule' do
        group_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, group: group)
        create(:protected_environment_approval_rule,
          protected_environment: protected_environment, access_level: Gitlab::Access::MAINTAINER)

        expect { project.protected_environments.revoke_group(group) }
          .to change { ProtectedEnvironments::ApprovalRule.exists?(group_rule.id) }.from(true).to(false)
      end
    end

    context 'when the project has multiple protected environments with different outcomes' do
      it 'preserves the sole-approver rule and deletes the redundant one', :aggregate_failures do
        other_environment = create(:protected_environment, project: project, name: 'staging')

        sole_approver_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, group: group)
        redundant_rule = create(:protected_environment_approval_rule,
          protected_environment: other_environment, group: group)
        create(:protected_environment_approval_rule,
          protected_environment: other_environment, user: create(:user))

        project.protected_environments.revoke_group(group)

        expect(ProtectedEnvironments::ApprovalRule.exists?(sole_approver_rule.id)).to be(true)
        expect(ProtectedEnvironments::ApprovalRule.exists?(redundant_rule.id)).to be(false)
      end
    end

    context 'when called unscoped on the class' do
      it 'raises instead of locking every protected environment in the instance' do
        expect { described_class.revoke_group(group) }.to raise_error(ArgumentError)
      end
    end

    context 'when called with a scope that does not constrain project_id' do
      it 'raises instead of locking every protected environment matching an unrelated attribute' do
        expect { described_class.where(name: 'production').revoke_group(group) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.reassign_sole_group_approver' do
    let_it_be(:group) { create(:group) }

    context 'when the group is the sole approver on an unrelated protected environment' do
      let_it_be_with_reload(:protected_environment) { create(:protected_environment) }
      let_it_be(:approval_rule) do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
      end

      it 'reassigns the rule to a maintainer-level fallback instead of leaving it pointing at the group',
        :aggregate_failures do
        described_class.reassign_sole_group_approver(group)

        approval_rule.reload
        expect(approval_rule.group_id).to be_nil
        expect(approval_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when the group is the sole approver on its own group-level protected environment' do
      let_it_be_with_reload(:protected_environment) { create(:protected_environment, :group_level, group: group) }
      let_it_be(:approval_rule) do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
      end

      it 'leaves the rule alone, since the environment is destroyed by the FK cascade along with the group itself' do
        described_class.reassign_sole_group_approver(group)

        approval_rule.reload
        expect(approval_rule.group_id).to eq(group.id)
      end
    end

    context 'when the group is the sole approver on a protected environment owned by its own subgroup' do
      it 'reassigns it too, since this method has no way to know the environment is about to be destroyed' do
        subgroup = create(:group, parent: group)
        subproject = create(:project, group: subgroup)
        protected_environment = create(:protected_environment, project: subproject)
        approval_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, group: group)

        described_class.reassign_sole_group_approver(group)

        approval_rule.reload
        expect(approval_rule.group_id).to be_nil
        expect(approval_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when the group is the sole approver on both its own and an unrelated protected environment' do
      let_it_be_with_reload(:own_environment) { create(:protected_environment, :group_level, group: group) }
      let_it_be(:own_approval_rule) do
        create(:protected_environment_approval_rule, protected_environment: own_environment, group: group)
      end

      let_it_be_with_reload(:unrelated_environment) { create(:protected_environment) }
      let_it_be(:unrelated_approval_rule) do
        create(:protected_environment_approval_rule, protected_environment: unrelated_environment, group: group)
      end

      it 'reassigns only the unrelated rule', :aggregate_failures do
        described_class.reassign_sole_group_approver(group)

        own_approval_rule.reload
        expect(own_approval_rule.group_id).to eq(group.id)

        unrelated_approval_rule.reload
        expect(unrelated_approval_rule.group_id).to be_nil
        expect(unrelated_approval_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when other approvers remain on the protected environment' do
      let_it_be_with_reload(:protected_environment) { create(:protected_environment) }
      let_it_be(:approval_rule) do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
      end

      it 'leaves the rule alone' do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, user: create(:user))

        described_class.reassign_sole_group_approver(group)

        approval_rule.reload
        expect(approval_rule.group_id).to eq(group.id)
      end
    end

    context 'when an approval rule found by the initial query is gone by the time it is locked' do
      it 'still reassigns the surviving environment and does not error on the vanished one', :aggregate_failures do
        surviving_environment = create(:protected_environment)
        surviving_rule = create(:protected_environment_approval_rule,
          protected_environment: surviving_environment, group: group)
        vanishing_environment = create(:protected_environment, project: create(:project), name: 'production')
        vanishing_rule = create(:protected_environment_approval_rule,
          protected_environment: vanishing_environment, group: group)

        # Simulates vanishing_rule being deleted concurrently, after the
        # initial pluck already found its protected_environment_id but
        # before this method locks it - `lock` here only returns rows
        # that still exist.
        allow(ProtectedEnvironments::ApprovalRule).to receive(:lock)
          .and_return(ProtectedEnvironments::ApprovalRule.where.not(id: vanishing_rule.id))

        expect { described_class.reassign_sole_group_approver(group) }.not_to raise_error

        surviving_rule.reload
        expect(surviving_rule.group_id).to be_nil
        expect(surviving_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when the group has multiple approval rules on the same protected environment' do
      let_it_be_with_reload(:protected_environment) { create(:protected_environment) }
      let_it_be(:rule_a) do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
      end

      let_it_be(:rule_b) do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)
      end

      it 'collapses them to one reassigned rule, since a second rule for the same approver can never be satisfied',
        :aggregate_failures do
        described_class.reassign_sole_group_approver(group)

        expect(ProtectedEnvironments::ApprovalRule.exists?(rule_b.id)).to be(false)

        rule_a.reload
        expect(rule_a.group_id).to be_nil
        expect(rule_a.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    it 'locks the approval rule rows, not the parent protected_environment row' do
      protected_environment = create(:protected_environment)
      create(:protected_environment_approval_rule, protected_environment: protected_environment, group: group)

      recorder = ActiveRecord::QueryRecorder.new { described_class.reassign_sole_group_approver(group) }

      expect(recorder.log).to include(a_string_matching(/SELECT.*"protected_environment_approval_rules".*FOR UPDATE/))
      expect(recorder.log).not_to include(a_string_matching(/SELECT.*"protected_environments".*FOR UPDATE/))
    end
  end

  describe '.reassign_sole_user_approver' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project) }
    let_it_be_with_reload(:protected_environment) do
      create(:protected_environment, project: project, name: 'production')
    end

    context 'when the user is the sole approver on the protected environment' do
      it 'reassigns the rule to a maintainer-level fallback instead of leaving it pointing at the user',
        :aggregate_failures do
        rule = create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)

        described_class.reassign_sole_user_approver(user)

        rule.reload
        expect(rule.user_id).to be_nil
        expect(rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when other approvers remain on the protected environment' do
      it 'leaves the rule alone' do
        rule = create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
        create(:protected_environment_approval_rule, protected_environment: protected_environment, user: create(:user))

        described_class.reassign_sole_user_approver(user)

        rule.reload
        expect(rule.user_id).to eq(user.id)
      end
    end

    context 'when a role-based approval rule remains on the protected environment' do
      it 'leaves the rule alone' do
        rule = create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
        create(:protected_environment_approval_rule, protected_environment: protected_environment,
          access_level: Gitlab::Access::MAINTAINER)

        described_class.reassign_sole_user_approver(user)

        rule.reload
        expect(rule.user_id).to eq(user.id)
      end
    end

    context 'when a group-based approval rule remains on the protected environment' do
      it 'leaves the rule alone' do
        rule = create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
        create(:protected_environment_approval_rule, protected_environment: protected_environment,
          group: create(:group))

        described_class.reassign_sole_user_approver(user)

        rule.reload
        expect(rule.user_id).to eq(user.id)
      end
    end

    context 'when the user has multiple approval rules on the same protected environment' do
      it 'collapses them to one reassigned rule, since a second rule for the same approver can never be satisfied',
        :aggregate_failures do
        rule_a = create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
        rule_b = create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)

        described_class.reassign_sole_user_approver(user)

        expect(ProtectedEnvironments::ApprovalRule.exists?(rule_b.id)).to be(false)

        rule_a.reload
        expect(rule_a.user_id).to be_nil
        expect(rule_a.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when the user is the sole approver in more than one project' do
      it 'reassigns the rule in every affected project', :aggregate_failures do
        other_project = create(:project)
        other_protected_environment = create(:protected_environment, project: other_project, name: 'production')

        rule_in_project = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: user)
        rule_in_other_project = create(:protected_environment_approval_rule,
          protected_environment: other_protected_environment, user: user)

        described_class.reassign_sole_user_approver(user)

        [rule_in_project, rule_in_other_project].each do |rule|
          rule.reload
          expect(rule.user_id).to be_nil
          expect(rule.access_level).to eq(Gitlab::Access::MAINTAINER)
        end
      end
    end

    context 'when an approval rule found by the initial query is gone by the time it is locked' do
      it 'still reassigns the surviving environment and does not error on the vanished one', :aggregate_failures do
        surviving_rule = create(:protected_environment_approval_rule,
          protected_environment: protected_environment, user: user)
        vanishing_environment = create(:protected_environment, project: create(:project), name: 'production')
        vanishing_rule = create(:protected_environment_approval_rule,
          protected_environment: vanishing_environment, user: user)

        # Simulates vanishing_rule being deleted concurrently, after the
        # initial pluck already found its protected_environment_id but
        # before this method locks it - `lock` here only returns rows
        # that still exist.
        allow(ProtectedEnvironments::ApprovalRule).to receive(:lock)
          .and_return(ProtectedEnvironments::ApprovalRule.where.not(id: vanishing_rule.id))

        expect { described_class.reassign_sole_user_approver(user) }.not_to raise_error

        surviving_rule.reload
        expect(surviving_rule.user_id).to be_nil
        expect(surviving_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    it 'locks the approval rule rows, not the parent protected_environment row' do
      create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)

      recorder = ActiveRecord::QueryRecorder.new { described_class.reassign_sole_user_approver(user) }

      expect(recorder.log).to include(a_string_matching(/SELECT.*"protected_environment_approval_rules".*FOR UPDATE/))
      expect(recorder.log).not_to include(a_string_matching(/SELECT.*"protected_environments".*FOR UPDATE/))
    end
  end

  describe '.for_environment' do
    let_it_be(:group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }

    let_it_be(:environment) { create(:environment, name: 'production', project: project) }
    let_it_be(:protected_environment) { create(:protected_environment, name: 'production', project: project) }

    subject { described_class.for_environment(environment) }

    it { is_expected.to match_array([protected_environment]) }

    it 'caches result', :request_store do
      described_class.for_environment(environment).to_a

      expect { described_class.for_environment(environment).to_a }
        .not_to exceed_query_limit(0)
    end

    context 'when environment does not exist' do
      let(:environment) { nil }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    it 'calls .for_environments with the environment' do
      expect(described_class).to receive(:for_environments).with([environment]).and_call_original

      described_class.for_environment(environment)
    end
  end

  describe '.for_environments' do
    let_it_be(:group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }

    let(:environments) { [create(:environment, name: 'production', project: project)] }
    let!(:protected_environment) { create(:protected_environment, name: 'production', project: project) }

    subject { described_class.for_environments(environments) }

    it { is_expected.to match_array([protected_environment]) }

    it 'raises an error if environments belong to more than one project' do
      expect { described_class.for_environments(create_list(:environment, 2)) }
        .to raise_error(ArgumentError, 'Environments must be in the same project')
    end

    context 'when environment is a different name' do
      let(:environments) { [create(:environment, name: 'staging', project: project)] }

      it { is_expected.to be_empty }
    end

    context 'when environment exists in a different project' do
      let(:environments) { [create(:environment, name: 'production', project: create(:project))] }

      it { is_expected.to be_empty }
    end

    context 'with group-level protected environment' do
      let_it_be(:group_protected_environment) do
        create(:protected_environment, :production, :group_level, group: group)
      end

      context 'with project-level production environment' do
        let(:environments) { [create(:environment, :production, project: project)] }

        it 'has multiple protections' do
          is_expected.to contain_exactly(protected_environment, group_protected_environment)
        end

        context 'when project-level protection does not exist' do
          let(:protected_environment) { nil }

          it 'has only group-level protection' do
            is_expected.to match_array([group_protected_environment])
          end
        end
      end

      context 'with staging environment' do
        let(:environments) { [create(:environment, :staging, project: project)] }

        it 'does not have any protections' do
          is_expected.to be_empty
        end
      end
    end

    context 'with multiple environments' do
      let(:protected_environment) { nil }
      let(:environments) do
        [
          create(:environment, name: 'production', project: project),
          create(:environment, name: 'canary', project: project),
          create(:environment, name: 'dev', project: project)
        ]
      end

      let_it_be(:protected_environments) do
        [
          create(:protected_environment, name: 'production', project: project),
          create(:protected_environment, name: 'canary', project: project)
        ]
      end

      it { is_expected.to match_array(protected_environments) }
    end
  end

  def create_deploy_access_level(protected_environment, **opts)
    protected_environment.deploy_access_levels.create!(**opts)
  end
end
