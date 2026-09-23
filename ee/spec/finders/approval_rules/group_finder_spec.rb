# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ApprovalRules::GroupFinder, feature_category: :source_code_management do
  let_it_be_with_reload(:rule) { create(:approval_project_rule) }
  let_it_be(:user) { create(:user) }
  let_it_be(:organization) { create(:common_organization) }
  let_it_be(:public_group) { create(:group, name: 'public_group', organization: organization) }
  let_it_be(:private_inaccessible_group) do
    create(:group, :private, name: 'private_inaccessible_group', organization: organization)
  end

  let_it_be(:private_accessible_group) do
    create(:group, :private, name: 'private_accessible_group', owners: user, organization: organization)
  end

  let_it_be(:private_accessible_subgroup) do
    create(:group, :private, parent: private_accessible_group, name: 'private_accessible_subgroup',
      organization: organization)
  end

  let_it_be(:private_shared_group) do
    create(:group, :private, name: 'private_shared_group', organization: organization)
  end

  let_it_be(:private_shared_group_link) do
    create(:project_group_link, project: rule.project, group: private_shared_group)
  end

  let_it_be(:public_shared_group) { create(:group, name: 'public_shared_group', organization: organization) }
  let_it_be(:public_shared_group_link) do
    create(:project_group_link, project: rule.project, group: public_shared_group)
  end

  subject(:finder) { described_class.new(rule, user) }

  context 'when with inaccessible groups' do
    before do
      rule.groups = [public_group, private_inaccessible_group, private_accessible_group, private_accessible_subgroup,
        private_shared_group]
    end

    it 'returns groups' do
      expect(finder.visible_groups).to contain_exactly(
        public_group, private_accessible_group, private_accessible_subgroup
      )
      expect(finder.hidden_groups).to contain_exactly(private_inaccessible_group, private_shared_group)
      expect(finder.contains_hidden_groups?).to be(true)
    end

    context 'when user is a member of the project' do
      let_it_be(:project_user) { create(:user, organization: organization) }

      before_all do
        rule.project.add_developer(project_user)
        private_accessible_group.add_developer(project_user)
      end

      describe '#hidden_groups' do
        subject(:hidden_groups) { described_class.new(rule, project_user).hidden_groups }

        it 'returns rule groups that the user cannot access except shared groups' do
          expect(hidden_groups).to contain_exactly(private_inaccessible_group)
        end

        context 'when the show_private_groups_as_approvers flag is disabled' do
          before do
            stub_feature_flags(show_private_groups_as_approvers: false)
          end

          it 'returns rule groups that the user cannot access' do
            expect(hidden_groups).to contain_exactly(private_inaccessible_group, private_shared_group)
          end
        end
      end
    end

    context 'when user is an admin', :enable_admin_mode do
      subject(:finder) { described_class.new(rule, create(:admin)) }

      it 'returns groups' do
        expect(finder.visible_groups).to contain_exactly(
          public_group,
          private_accessible_group,
          private_accessible_subgroup,
          private_inaccessible_group,
          private_shared_group
        )
        expect(finder.hidden_groups).to be_empty
        expect(finder.contains_hidden_groups?).to be(false)
      end
    end

    context 'when user is not authorized' do
      subject(:finder) { described_class.new(rule, nil) }

      it 'returns only public groups' do
        expect(finder.visible_groups).to contain_exactly(
          public_group
        )
        expect(finder.hidden_groups).to contain_exactly(
          private_accessible_group, private_accessible_subgroup, private_inaccessible_group, private_shared_group
        )
        expect(finder.contains_hidden_groups?).to be(true)
      end
    end

    context 'when avoiding N+1 queries', :request_store do
      it 'avoids N+1 database queries' do
        rule.reload

        control = ActiveRecord::QueryRecorder.new { finder.visible_groups }

        # Clear cached association and request cache
        rule.reload
        RequestStore.clear!

        rule.groups << create(
          :group,
          :private,
          parent: private_accessible_group,
          name: 'private_accessible_subgroup2',
          organization: organization
        )

        expect { described_class.new(rule, user).visible_groups }.not_to exceed_query_limit(control)
      end
    end
  end

  context 'when without inaccessible groups' do
    before do
      rule.groups = [public_group, private_accessible_group, private_accessible_subgroup]
    end

    it 'returns groups' do
      expect(finder.visible_groups).to contain_exactly(
        public_group, private_accessible_group, private_accessible_subgroup
      )
      expect(finder.hidden_groups).to be_empty
      expect(finder.contains_hidden_groups?).to be(false)
    end
  end

  describe '#contains_hidden_groups?' do
    context 'when the rule has no groups' do
      before do
        rule.groups = []
      end

      it 'returns false' do
        expect(finder.contains_hidden_groups?).to be(false)
      end

      it 'issues no group queries when the groups association is preloaded' do
        # Mirrors the approval-state read path, where rule.groups is preloaded.
        rule.groups.load

        recorder = ActiveRecord::QueryRecorder.new { finder.contains_hidden_groups? }

        expect(recorder.count).to eq(0)
      end
    end

    context 'when the rule allows any approver' do
      let_it_be(:any_approver_rule) do
        create(:approval_project_rule, :any_approver_rule, project: rule.project)
      end

      it 'returns false without querying groups or looking up invited groups', :aggregate_failures do
        expect(user).not_to receive(:can?)
        expect(described_class.new(any_approver_rule, user).contains_hidden_groups?).to be(false)

        recorder = ActiveRecord::QueryRecorder.new do
          described_class.new(any_approver_rule, user).contains_hidden_groups?
        end

        expect(recorder.count).to eq(0)
      end
    end

    context 'when the rule has groups that are not preloaded' do
      before do
        rule.groups = [private_inaccessible_group]
        rule.reload
      end

      it 'does not issue an extra query to check whether groups exist' do
        finder = described_class.new(rule, user)
        finder.hidden_groups

        recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          finder.contains_hidden_groups?
        end

        expect(recorder.count).to eq(1)
      end
    end

    context 'with multiple grouped rules for the same project', :request_store do
      let_it_be(:project) { rule.project }
      let_it_be(:authorized_user) { create(:user, developer_of: project) }
      let_it_be(:other_authorized_user) { create(:user, developer_of: project) }
      let_it_be(:unauthorized_user) { create(:user) }

      let_it_be(:rules) do
        create_list(:approval_project_rule, 5, project: project).tap do |project_rules|
          project_rules.each { |approval_rule| approval_rule.groups << private_shared_group }
        end
      end

      it 'loads invited group ids once', :aggregate_failures do
        rules.each(&:reload)

        recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          rules.each_with_index do |approval_rule, index|
            current_user = index.even? ? authorized_user : other_authorized_user

            described_class.new(approval_rule, current_user).contains_hidden_groups?
          end
        end

        invited_group_lookup_queries = recorder.log.select do |query|
          query.include?('"project_group_links"')
        end

        expect(invited_group_lookup_queries).not_to be_empty
        expect(invited_group_lookup_queries.count).to eq(1)
      end

      it 'applies the authorization gate separately for each user', :aggregate_failures do
        authorized_hidden_groups = described_class.new(rules.first, authorized_user).hidden_groups
        unauthorized_hidden_groups = described_class.new(rules.second, unauthorized_user).hidden_groups

        expect(authorized_hidden_groups).to be_empty
        expect(unauthorized_hidden_groups).to contain_exactly(private_shared_group)
      end
    end
  end
end
