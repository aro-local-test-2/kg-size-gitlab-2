# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Security::ProjectTrackedContexts::Destroy, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:guest) { create(:user) }
  let_it_be(:project) { create(:project, :small_repo, maintainers: maintainer, guests: guest) }

  let(:current_user) { maintainer }

  before do
    stub_licensed_features(security_dashboard: true)
  end

  it { expect(described_class).to require_graphql_authorizations(:delete_security_project_tracked_ref) }

  describe 'GraphQL integration tests' do
    let!(:tracked_context) do
      create(:security_project_tracked_context, :tracked,
        project: project,
        context_name: 'feature-branch',
        context_type: :branch,
        is_default: false)
    end

    let(:query) do
      <<~GQL
        mutation($input: SecurityRefsUntrackInput!) {
          securityRefsUntrack(input: $input) {
            untrackedRefIds
            errors
            clientMutationId
          }
        }
      GQL
    end

    let(:variables) do
      {
        input: {
          refIds: [tracked_context.to_global_id.to_s],
          clientMutationId: "test-mutation-id"
        }
      }
    end

    subject(:result) { GitlabSchema.execute(query, variables: variables, context: { current_user: current_user }) }

    context 'when user has permission' do
      it 'destroys the tracked context and returns the expected payload', :aggregate_failures do
        expect { result }.to change { Security::ProjectTrackedContext.count }.by(-1)

        expect(result['errors']).to be_blank
        expect(result.dig('data', 'securityRefsUntrack')).to include(
          'untrackedRefIds' => [tracked_context.to_global_id.to_s],
          'errors' => [],
          'clientMutationId' => 'test-mutation-id'
        )
      end

      context 'when untracking multiple refs' do
        let!(:tracked_context_2) do
          create(:security_project_tracked_context, :tracked,
            project: project,
            context_name: 'v1.0.0',
            context_type: :tag,
            is_default: false)
        end

        let(:variables) do
          {
            input: {
              refIds: [
                tracked_context.to_global_id.to_s,
                tracked_context_2.to_global_id.to_s
              ],
              clientMutationId: "multi-ref-test"
            }
          }
        end

        it 'destroys multiple tracked contexts and returns the expected payload', :aggregate_failures do
          expect { result }.to change { Security::ProjectTrackedContext.count }.by(-2)

          expect(result['errors']).to be_blank
          untracked_ref_ids = result.dig('data', 'securityRefsUntrack', 'untrackedRefIds')
          expect(untracked_ref_ids.size).to eq(2)
          expect(untracked_ref_ids).to contain_exactly(
            tracked_context.to_global_id.to_s,
            tracked_context_2.to_global_id.to_s
          )
          expect(result.dig('data', 'securityRefsUntrack', 'errors')).to be_empty
          expect(result.dig('data', 'securityRefsUntrack', 'clientMutationId')).to eq('multi-ref-test')
        end
      end

      context 'when trying to delete default branch tracking' do
        let!(:tracked_context) do
          create(:security_project_tracked_context, :tracked,
            project: project,
            context_name: project.default_branch,
            context_type: :branch,
            is_default: true)
        end

        it 'prevents deletion, returns error, and does not destroy the tracked context', :aggregate_failures do
          expect { result }.not_to change { Security::ProjectTrackedContext.count }

          expect(result['errors']).to be_blank
          expect(result.dig('data', 'securityRefsUntrack', 'errors')).to include(
            match(/Cannot untrack default branch/)
          )
          expect(result.dig('data', 'securityRefsUntrack', 'untrackedRefIds')).to be_empty
        end
      end

      context 'when tracked context does not exist' do
        let(:variables) do
          {
            input: {
              refIds: [GlobalID.parse("gid://gitlab/Security::ProjectTrackedContext/#{non_existing_record_id}").to_s],
              clientMutationId: "test-mutation-id"
            }
          }
        end

        it 'returns not found error through GraphQL' do
          expect(result['errors']).to be_present
          expect(result['errors'].first['message'])
            .to eq(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
        end
      end
    end

    context 'when user lacks permission' do
      let(:current_user) { guest }

      it 'returns authorization error through GraphQL' do
        expect(result['errors']).to be_present
        expect(result['errors'].first['message'])
          .to eq(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
      end
    end

    context 'when user is not authenticated' do
      let(:current_user) { nil }

      it 'returns authentication error through GraphQL' do
        expect(result['errors']).to be_present
      end
    end
  end
end
