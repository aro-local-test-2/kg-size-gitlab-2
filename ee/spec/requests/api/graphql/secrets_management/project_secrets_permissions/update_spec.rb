# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Update Project Secrets Permission', :gitlab_secrets_manager, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project_group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: project_group) }
  let_it_be_with_reload(:shared_group) { project_group }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:mutation_name) { :project_secrets_permission_update }

  let(:resource) { project }
  let(:secrets_manager) { create(:project_secrets_manager, project: project) }
  let(:secrets_manager_namespace_path) { secrets_manager.full_project_namespace_path }
  let(:service_class) { SecretsManagement::ProjectSecretsPermissions::UpdateService }
  let(:feature_flag_name) { :secrets_manager }

  let(:params) do
    {
      projectPath: project.full_path,
      principal: principal_params,
      actions: actions,
      expiredAt: expired_at
    }
  end

  let(:mutation) { graphql_mutation(mutation_name, params) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  def provision_secrets_manager(secrets_manager, user)
    provision_project_secrets_manager(secrets_manager, user)
  end

  it_behaves_like 'a GraphQL mutation for updating secrets permissions', 'project'

  context 'with granular token authorization' do
    let_it_be(:other_user) { create(:user) }

    let(:actions) { %w[READ WRITE] }
    let(:expired_at) { 1.week.from_now.to_date.iso8601 }
    let(:principal_params) { { id: other_user.id, type: 'USER' } }

    before_all do
      project.add_developer(other_user)
      project.add_owner(current_user)
    end

    before do
      provision_secrets_manager(secrets_manager, current_user)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_secrets_permission do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
