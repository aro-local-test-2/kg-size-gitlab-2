# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Resyncs security policies for a project/namespace',
  feature_category: :security_policy_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:project) { create(:project, :with_security_orchestration_policy_configuration) }
  let_it_be(:namespace) { create(:group, :with_security_orchestration_policy_configuration) }

  let(:current_user) { owner }

  context 'with granular token authorization' do
    before_all do
      project.add_owner(owner)
      namespace.add_owner(owner)
    end

    before do
      stub_licensed_features(security_orchestration_policies: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_policy do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:mutation) do
        graphql_mutation(:resync_security_policies, { full_path: project.full_path }, 'errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_security_policy do
      let(:user) { current_user }
      let(:boundary_object) { namespace }
      let(:mutation) do
        graphql_mutation(:resync_security_policies, { full_path: namespace.full_path }, 'errors')
      end

      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
