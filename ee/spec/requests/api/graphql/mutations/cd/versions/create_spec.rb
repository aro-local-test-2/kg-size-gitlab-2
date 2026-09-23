# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Create a continuous deployment version', feature_category: :continuous_delivery do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:service) { create(:cd_service, application: application) }
  let_it_be(:artifact_source) { create(:cd_artifact_source, service: service) }
  let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:organization_member) { create(:organization_user, organization: organization).user }

  let(:current_user) { organization_owner }
  let(:input) do
    {
      artifact_source_id: artifact_source.to_global_id.to_s,
      name: '2026.08.19-external/build+7'
    }
  end

  let(:mutation) { graphql_mutation(:cd_version_create, input) }
  let(:mutation_response) { graphql_mutation_response(:cd_version_create) }

  context 'when the user is an organization owner' do
    it 'creates an unverified version on the artifact source' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { ::Cd::Version.count }.by(1)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['version']).to include('name' => '2026.08.19-external/build+7', 'verified' => false)
      expect(::Cd::Version.last).to have_attributes(
        artifact_source: artifact_source,
        name: '2026.08.19-external/build+7',
        verified: false
      )
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_cd_artifact_source do
      let(:user) { current_user }
      let(:boundary_object) { :instance }
      let(:mutation) { graphql_mutation(:cd_version_create, input, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    context 'when name is blank' do
      let(:input) { super().merge(name: '') }

      it 'returns errors in the response' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { ::Cd::Version.count }

        expect(mutation_response['version']).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/Name can't be blank/))
      end
    end

    context 'when a version with the same name already exists for the artifact source' do
      before do
        create(:cd_version, :unverified, artifact_source: artifact_source, name: '2026.08.19-external/build+7')
      end

      it 'returns errors in the response' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { ::Cd::Version.count }

        expect(mutation_response['version']).to be_nil
        expect(mutation_response['errors']).to include(a_string_matching(/Name has already been taken/))
      end
    end

    context 'when name is not provided' do
      let(:input) { super().tap { |i| i.delete(:name) } }

      it 'returns a top-level argument error and does not create the version' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { ::Cd::Version.count }

        expect_graphql_errors_to_include(/was provided invalid value for name/)
      end
    end

    context 'when artifact_source_id is not provided' do
      let(:input) { super().tap { |i| i.delete(:artifact_source_id) } }

      it 'returns a top-level argument error and does not create the version' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { ::Cd::Version.count }

        expect_graphql_errors_to_include(/was provided invalid value for artifactSourceId/)
      end
    end
  end

  context 'when the user is an organization member' do
    let(:current_user) { organization_member }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the user is not a member of the organization' do
    let(:current_user) { create(:user) }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the ai_native_deploy feature flag is disabled' do
    before do
      stub_feature_flags(ai_native_deploy: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not create the version' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { ::Cd::Version.count }
    end
  end
end
