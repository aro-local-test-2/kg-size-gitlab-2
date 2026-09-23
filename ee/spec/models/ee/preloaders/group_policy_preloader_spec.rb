# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Preloaders::GroupPolicyPreloader, feature_category: :shared do
  let_it_be(:user) { create(:user) }
  let_it_be(:root_parent) { create(:group, :private, name: 'root-1', path: 'root-1') }
  let_it_be(:guest_group) { create(:group, name: 'public guest', path: 'public-guest', guests: user) }
  let_it_be(:private_maintainer_group) { create(:group, :private, name: 'b private maintainer', path: 'b-private-maintainer', parent: root_parent, maintainers: user) }
  let_it_be(:private_developer_group) { create(:group, :private, project_creation_level: nil, name: 'c public developer', path: 'c-public-developer', developers: user) }
  let_it_be(:public_maintainer_group) { create(:group, :private, name: 'a public maintainer', path: 'a-public-maintainer', maintainers: user) }

  let(:base_groups) { [guest_group, private_maintainer_group, private_developer_group, public_maintainer_group] }

  context 'when ip_restrictions feature is enabled' do
    before do
      stub_licensed_features(group_ip_restriction: true)
    end

    it 'avoids N+1 queries when authorizing a list of groups', :request_store, :use_sql_query_cache do
      authorize_groups(pristine_groups(base_groups))

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        authorize_groups(pristine_groups(base_groups))
      end

      new_groups = [
        create(:group, :private, maintainers: user),
        create(:group, :private, parent: private_maintainer_group),
        create(:group, :private, parent: create(:group, :private, name: 'root-3', path: 'root-3'), maintainers: user)
      ]

      expect { authorize_groups(pristine_groups(base_groups + new_groups)) }
        .to issue_same_number_of_queries_as(control)
    end
  end

  def pristine_groups(group_list)
    Group.id_in(group_list).to_a
  end

  def authorize_groups(group_list)
    described_class.new(group_list, user).execute

    group_list.each { |group| user.can?(:read_group, group) }
  end
end
