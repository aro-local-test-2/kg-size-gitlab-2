# frozen_string_literal: true

RSpec.shared_context 'group with enterprise users in group members' do
  let_it_be(:user_member) { create(:user, maintainer_of: group) }
  let_it_be(:enterprise_user_member) { create(:enterprise_user, enterprise_group: group, maintainer_of: group) }
end

RSpec.shared_context 'group with enterprise users from another group in group members' do
  let_it_be(:another_group) { create(:group, owners: owner) }
  let_it_be(:enterprise_user_member_from_another_group) do
    create(:enterprise_user, enterprise_group: another_group, maintainer_of: group)
  end
end

RSpec.shared_context 'subgroup with enterprise users in group members' do
  let_it_be(:user_member_in_subgroup) { create(:user) }
  let_it_be(:enterprise_user_member_in_subgroup) { create(:enterprise_user, enterprise_group: group) }
  let_it_be(:subgroup) do
    create(:group, parent: group, developers: [user_member_in_subgroup, enterprise_user_member_in_subgroup])
  end
end

RSpec.shared_context 'project with enterprise users in project members' do
  let_it_be(:user_member) { create(:user) }
  let_it_be(:enterprise_user_member) { create(:enterprise_user, enterprise_group: group) }

  before_all do
    project.add_maintainer(user_member)
    project.add_maintainer(enterprise_user_member)
  end
end

RSpec.shared_context 'project with enterprise users from another group in project members' do
  let_it_be(:another_group) { create(:group) }
  let_it_be(:enterprise_user_member_from_another_group) { create(:enterprise_user, enterprise_group: another_group) }

  before_all do
    another_group.add_owner(owner)

    project.add_maintainer(enterprise_user_member_from_another_group)
  end
end
