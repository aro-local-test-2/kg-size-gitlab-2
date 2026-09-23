# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reading Artifact Registry repository detail fields', feature_category: :artifact_registry do
  include GraphqlHelpers

  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }
  let_it_be(:creator) { create(:user) }
  let_it_be(:updater) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:repository_name) { 'my-repo' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:created_by) { creator.id.to_s }
  let(:updated_by) { updater.id.to_s }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'artifacts_count' => 12,
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'created_at' => '2026-07-01T10:00:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'created_by' => created_by,
      'updated_by' => updated_by
    }
  end

  let(:query) do
    graphql_query_for(
      :organization,
      { id: organization.to_global_id.to_s },
      query_graphql_field(
        :artifact_registry_repository,
        { name: repository_name },
        <<~FIELDS
          artifactsCount
          createdAt
          createdBy { id username }
          updatedBy { id username }
        FIELDS
      )
    )
  end

  let(:repository_data) { graphql_data.dig('organization', 'artifactRegistryRepository') }

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      stub_request(:get, repository_url)
        .to_return(status: 200, headers: json_headers, body: repository_body.to_json)
    end

    it 'returns the counts, timestamp, and resolved users', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(repository_data).to include(
        'artifactsCount' => '12',
        'createdAt' => '2026-07-01T10:00:00+00:00',
        'createdBy' => a_graphql_entity_for(creator, :username),
        'updatedBy' => a_graphql_entity_for(updater, :username)
      )
    end
  end

  context 'when an attribution id has no matching user', :aggregate_failures do
    where(:case_name, :attribution) do
      'the ids are null'          | { 'created_by' => nil, 'updated_by' => nil }
      'the payload omits the ids' | {}
      'the ids are empty strings' | { 'created_by' => '', 'updated_by' => '' }
      'the ids point at no user'  | { 'created_by' => non_existing_record_id.to_s,
                                      'updated_by' => non_existing_record_id.to_s }
    end

    with_them do
      let(:repository_body) { super().except('created_by', 'updated_by').merge(attribution) }

      before do
        stub_request(:get, repository_url)
          .to_return(status: 200, headers: json_headers, body: repository_body.to_json)
      end

      it 'resolves the join to null rather than erroring' do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_data).to include('createdBy' => nil, 'updatedBy' => nil)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    it 'resolves to null and makes no HTTP call', :aggregate_failures do
      request = stub_request(:get, repository_url)

      stub_feature_flags(artifact_registry_ui: false)

      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(repository_data).to be_nil
      expect(request).not_to have_been_requested
    end
  end

  # Criterion 4: resolving the user joins across a list page must issue one batched Rails user
  # query, not one per row. Asserted against the list connection because that is what fans out;
  # the single-repository read returns one node.
  describe 'batching the user joins across the list connection' do
    let_it_be(:users) { create_list(:user, 3) }

    let(:repositories_url) { "#{base_url}/api/v1/#{slug}/repositories" }
    let(:page_size) { 20 }

    let(:page_body) do
      users.each_index.map do |index|
        {
          'id' => "0000000#{index}-0000-0000-0000-000000000000",
          'name' => "repo-#{index}",
          'format' => 'maven',
          'kind' => 'hosted',
          'visibility' => 'private',
          'artifacts_count' => index,
          'downloads_count' => 0,
          'size_bytes' => 0,
          'created_at' => '2026-07-01T10:00:00Z',
          'last_updated_at' => nil,
          'created_by' => users[index].id.to_s,
          'updated_by' => users[(index + 1) % users.size].id.to_s
        }
      end
    end

    let(:list_query) do
      <<~QUERY
        query($id: OrganizationsOrganizationID!, $first: Int) {
          organization(id: $id) {
            artifactRegistryRepositories(first: $first) {
              nodes {
                name
                createdBy { id }
                updatedBy { id }
              }
            }
          }
        }
      QUERY
    end

    before do
      stub_request(:get, repositories_url)
        .with(query: { limit: page_size.to_s, sort: 'last_updated_at', order: 'desc' })
        .to_return(status: 200, headers: json_headers, body: { 'repositories' => page_body }.to_json)
    end

    it 'issues a single users query for the whole page and attaches each row its own users' do
      recorder = ActiveRecord::QueryRecorder.new do
        post_graphql(list_query, current_user: current_user,
          variables: { id: organization.to_global_id.to_s, first: page_size })
      end

      expect(graphql_errors).to be_nil
      expect(recorder.log.grep(/FROM "users"/).size).to eq(1)
      expect(graphql_data.dig('organization', 'artifactRegistryRepositories', 'nodes')).to eq(
        users.each_with_index.map do |user, index|
          {
            'name' => "repo-#{index}",
            'createdBy' => { 'id' => user.to_global_id.to_s },
            'updatedBy' => { 'id' => users[(index + 1) % users.size].to_global_id.to_s }
          }
        end
      )
    end
  end
end
