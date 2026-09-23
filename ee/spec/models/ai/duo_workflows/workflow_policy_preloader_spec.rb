# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowPolicyPreloader, feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }
  let_it_be(:root_group) { create(:group, developers: user) }
  let_it_be(:saml_provider) { create(:saml_provider, group: root_group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:project) { create(:project, group: root_group) }
  let_it_be(:other_project) { create(:project, group: subgroup) }

  let_it_be(:project_workflows) do
    [project, other_project].map { |p| create(:duo_workflows_workflow, project: p, user: user) }
  end

  let_it_be(:group_workflow) { create(:duo_workflows_workflow, namespace: subgroup, user: user) }

  let(:workflows) do
    ::Ai::DuoWorkflows::Workflow.id_in(project_workflows + [group_workflow]).with_preloaded_associations.to_a
  end

  subject(:execute) { described_class.new(workflows, user).execute }

  it 'shares one root ancestor object across every container', :aggregate_failures do
    execute

    roots = workflows.map { |workflow| (workflow.project || workflow.namespace).root_ancestor }
    project_group_roots = workflows.filter_map(&:project).map { |p| p.group.root_ancestor }

    expect((roots + project_group_roots).map(&:id).uniq).to eq([root_group.id])
    expect((roots + project_group_roots).uniq(&:object_id)).to have_attributes(size: 1)
    expect(roots.first.association(:saml_provider)).to be_loaded
    expect(roots.first.association(:namespace_settings)).to be_loaded
    expect(roots.first.association(:ai_settings)).to be_loaded
  end

  it 'loads the project associations the policy reads', :aggregate_failures do
    execute

    workflows.filter_map(&:project).each do |loaded_project|
      expect(loaded_project.association(:project_setting)).to be_loaded
      expect(loaded_project.association(:organization)).to be_loaded
      expect(loaded_project.association(:project_namespace)).to be_loaded
      expect(loaded_project.association(:group)).to be_loaded
    end
  end

  it 'primes the max access level for every container', :request_store, :aggregate_failures do
    execute

    expect { project.team.max_member_access(user.id) }.not_to exceed_query_limit(0).for_model(ProjectAuthorization)
    expect do
      other_project.team.max_member_access(user.id)
    end.not_to exceed_query_limit(0).for_model(ProjectAuthorization)
    expect { subgroup.max_member_access_for_user(user) }.not_to exceed_query_limit(0).for_model(Member)
  end

  it 'does nothing for an empty page' do
    expect { described_class.new([], user).execute }.not_to raise_error
  end

  context 'with a session in a personal project' do
    let_it_be(:personal_project) { create(:project, :in_user_namespace) }

    let_it_be(:personal_workflow) { create(:duo_workflows_workflow, project: personal_project, user: user) }

    let(:workflows) do
      ::Ai::DuoWorkflows::Workflow.id_in(project_workflows + [personal_workflow]).with_preloaded_associations.to_a
    end

    it 'assigns the user namespace as root without loading a SAML provider on it', :aggregate_failures do
      expect { execute }.not_to raise_error

      loaded_projects = workflows.filter_map(&:project)
      personal_root = loaded_projects.find { |p| p.id == personal_project.id }.namespace.root_ancestor
      group_root = loaded_projects.find { |p| p.id == project.id }.namespace.root_ancestor

      expect(personal_root).to be_a(Namespaces::UserNamespace)
      expect(personal_root.association(:namespace_settings)).to be_loaded
      expect(group_root.association(:saml_provider)).to be_loaded
    end
  end
end
