# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Bulk revoking Artifact Registry roles', feature_category: :system_access do
  include GraphqlHelpers

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: current_organization) }
  let_it_be(:assignee) { create(:user, organization: current_organization) }
  let_it_be(:assignee_b) { create(:user, organization: current_organization) }

  let(:resource_id) { Gitlab::Utils.uuid_v7 }
  let(:revocations) do
    [{ 'assigneeId' => assignee.to_global_id.to_s, 'resourceId' => resource_id }]
  end

  let(:mutation) { graphql_mutation(:artifact_registry_role_bulk_revoke, { 'revocations' => revocations }) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_role_bulk_revoke)
  end

  before do
    # The token exchange has its own specs; stub the minted token so this spec
    # stays focused on the GraphQL-to-IAM delete path.
    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: 'ar-token')
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)

    # Stub IAM data access service config so the ServiceTokenInterceptor can be
    # constructed without reading from disk (secret file is not present in CI).
    allow(Authn::IamDataAccessService).to receive_messages(
      grpc_address: 'localhost:5005',
      secret: 'test-service-token'
    )
  end

  it 'deletes every assignment in IAM in one call and returns no errors', :aggregate_failures do
    revokes = [
      { 'assigneeId' => assignee.to_global_id.to_s, 'resourceId' => resource_id },
      { 'assigneeId' => assignee_b.to_global_id.to_s, 'resourceId' => resource_id }
    ]
    captured_request = nil

    expect_next_instance_of(::Gitlab::Iam::Update::V1::UpdateService::Stub) do |stub|
      expect(stub).to receive(:delete_relationships) do |request, metadata:|
        captured_request = request
        expect(metadata['authorization']).to eq('Bearer ar-token')

        ::Gitlab::Iam::Update::V1::DeleteRelationshipsResponse.new
      end
    end

    post_graphql_mutation(graphql_mutation(:artifact_registry_role_bulk_revoke, { 'revocations' => revokes }),
      current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(mutation_response['errors']).to be_empty
    expect(mutation_response['revokedRoleCount']).to eq(2)

    expect(captured_request.keys.size).to eq(2)
    expect(captured_request.keys.map { |k| k.subject.identity.local_id })
      .to match_array([assignee.id.to_s, assignee_b.id.to_s])
    expect(captured_request.keys.map { |k| k.subject.identity.origin_id })
      .to all(eq(current_organization.uuid))
    expect(captured_request.keys.map(&:kind)).to all(eq(:KIND_ASSIGNMENT))
  end

  context 'when IAM rejects the delete' do
    it 'surfaces the error in the mutation response' do
      allow_next_instance_of(::Gitlab::Iam::Update::V1::UpdateService::Stub) do |stub|
        allow(stub).to receive(:delete_relationships)
          .and_raise(GRPC::NotFound.new('subject not found'))
      end

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_present
    end
  end

  context 'when a revocation is invalid' do
    it 'reports a nonexistent user as not found in the payload errors' do
      revokes = [{
        'assigneeId' => "gid://gitlab/User/#{non_existing_record_id}",
        'resourceId' => resource_id
      }]

      post_graphql_mutation(graphql_mutation(:artifact_registry_role_bulk_revoke, { 'revocations' => revokes }),
        current_user: current_user)

      expect(mutation_response['errors']).to include(a_string_matching(/could not be found/))
    end

    it 'surfaces a validation error in the payload errors' do
      revokes = [{
        'assigneeId' => assignee.to_global_id.to_s,
        'resourceId' => 'not-a-uuid'
      }]

      post_graphql_mutation(graphql_mutation(:artifact_registry_role_bulk_revoke, { 'revocations' => revokes }),
        current_user: current_user)

      expect(mutation_response['errors']).to include(a_string_matching(/UUIDv7/))
    end
  end

  it 'resolves the assignees without an N+1 query' do
    # The service is mocked here to isolate the mutation's assignee batch-load
    # from the IAM delete and token exchange.
    allow_next_instances_of(::Authz::ArtifactRegistry::RevokeRoleAssignmentsService, nil) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success)
    end

    revoke_for = ->(user) do
      { 'assigneeId' => user.to_global_id.to_s, 'resourceId' => resource_id }
    end
    run = ->(revokes) do
      post_graphql_mutation(graphql_mutation(:artifact_registry_role_bulk_revoke, { 'revocations' => revokes }),
        current_user: current_user)
    end

    run.call([revoke_for.call(assignee)]) # warm up
    control = ActiveRecord::QueryRecorder.new { run.call([revoke_for.call(assignee)]) }

    expect { run.call([revoke_for.call(assignee), revoke_for.call(assignee_b)]) }
      .not_to exceed_query_limit(control)
  end

  context 'when the user is not authenticated' do
    it 'returns a top-level error and does not call the service' do
      expect(::Authz::ArtifactRegistry::RevokeRoleAssignmentsService).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: nil)

      expect(graphql_errors).to be_present
    end
  end
end
