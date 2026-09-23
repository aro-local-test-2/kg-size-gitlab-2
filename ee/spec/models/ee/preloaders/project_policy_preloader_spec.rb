# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Preloaders::ProjectPolicyPreloader, feature_category: :shared do
  let_it_be(:user) { create(:user) }
  let_it_be(:root_parent) { create(:group, :private, name: 'root-1', path: 'root-1') }
  let_it_be(:guest_project) { create(:project, name: 'public guest', path: 'public-guest', guests: user) }
  let_it_be(:private_maintainer_project) do
    create(:project, :private, name: 'b private maintainer', path: 'b-private-maintainer', namespace: root_parent,
      maintainers: user)
  end

  let_it_be(:private_developer_project) do
    create(:project, :private, name: 'c public developer', path: 'c-public-developer', developers: user)
  end

  let_it_be(:public_maintainer_project) do
    create(:project, :private, name: 'a public maintainer', path: 'a-public-maintainer', maintainers: user)
  end

  let(:base_projects) do
    [guest_project, private_maintainer_project, private_developer_project, public_maintainer_project]
  end

  it 'avoids N+1 queries when authorizing a list of projects', :request_store do
    control_projects = preloaded_projects(base_projects)

    control = ActiveRecord::QueryRecorder.new { authorize_projects(control_projects) }

    new_projects = [
      create(:project, :private, maintainers: user),
      create(:project, :private, namespace: root_parent, maintainers: user),
      create(:project, :private, namespace: create(:group, :private, name: 'root-3', path: 'root-3'),
        maintainers: user)
    ]

    action_projects = preloaded_projects(base_projects + new_projects)

    expect { authorize_projects(action_projects) }.not_to exceed_query_limit(control)
  end

  def preloaded_projects(project_list)
    Project.id_in(project_list).tap { |projects| described_class.new(projects, user).execute }
  end

  def authorize_projects(project_list)
    project_list.each { |project| user.can?(:read_code, project) }
  end
end
