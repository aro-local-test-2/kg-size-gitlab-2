# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository upstream list', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:non_member) { create(:user) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-virtual' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:upstreams_url) { "#{repository_url}/#{format}/upstream_repositories" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'virtual',
      'visibility' => 'private',
      'description' => 'A virtual repository',
      'settings' => {}
    }
  end

  let(:first_upstream) do
    {
      'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
      'position' => 1,
      'upstream_repository' => {
        'id' => 'aaaa1111-0000-0000-0000-000000000000',
        'name' => "#{format}-hosted",
        'format' => format,
        'kind' => 'hosted'
      }
    }
  end

  let(:second_upstream) do
    {
      'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
      'position' => 2,
      'upstream_repository' => {
        'id' => 'bbbb2222-0000-0000-0000-000000000000',
        'name' => "#{format}-remote",
        'format' => format,
        'kind' => 'remote'
      }
    }
  end

  let(:upstreams_body) { [first_upstream, second_upstream] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryRepositoryUpstreams(
        $id: OrganizationsOrganizationID!
        $name: String!
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            upstreamRepositories {
              id
              position
              upstreamRepository {
                id
                name
                format
                kind
              }
            }
          }
        }
      }
    QUERY
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end
  end

  subject(:post_query) do
    post_graphql(query, current_user: current_user,
      variables: { id: organization.to_global_id.to_s, name: repository_name })
  end

  shared_examples 'resolving the list null while the repository still renders' do
    it 'renders a null list, no error, and the repository around it', :aggregate_failures do
      stub_repository_read

      post_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(upstreams_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'rendering the service-unavailable error beside the loaded repository' do
    it 'renders the service-unavailable error and keeps the repository rendered', :aggregate_failures do
      stub_repository_read

      post_query

      expect(upstreams_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  context 'when the repository is virtual' do
    where(:format, :repository_name) do
      [
        %w[maven maven-virtual],
        %w[npm npm-virtual],
        %w[docker docker-virtual],
        %w[oci oci-virtual]
      ]
    end

    with_them do
      it 'renders each association in position order, with its upstream summary discriminated by kind' do
        stub_repository_read
        stub_upstreams_list

        post_query

        expect(upstreams_response).to eq(
          [
            {
              'id' => 'e5f6a7b8-0000-0000-0000-000000000000',
              'position' => 1,
              'upstreamRepository' => {
                'id' => 'aaaa1111-0000-0000-0000-000000000000',
                'name' => "#{format}-hosted",
                'format' => format.upcase,
                'kind' => 'HOSTED'
              }
            },
            {
              'id' => 'f6a7b8c9-0000-0000-0000-000000000000',
              'position' => 2,
              'upstreamRepository' => {
                'id' => 'bbbb2222-0000-0000-0000-000000000000',
                'name' => "#{format}-remote",
                'format' => format.upcase,
                'kind' => 'REMOTE'
              }
            }
          ]
        )
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository holds no upstreams yet' do
    let(:upstreams_body) { [] }

    it 'renders an empty list rather than a null one or an error', :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response).to eq([])
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository resolves its full upstream set' do
    let(:upstreams_body) do
      Array.new(20) do |i|
        {
          'id' => "assoc-#{i}-0000-0000-0000-000000000000",
          'position' => i + 1,
          'upstream_repository' => {
            'id' => "up-#{i}-0000-0000-0000-000000000000",
            'name' => "upstream-#{i}",
            'format' => format,
            'kind' => 'hosted'
          }
        }
      end
    end

    it 'reads the whole list in exactly one Artifact Registry request', :aggregate_failures do
      stub_repository_read
      list = stub_upstreams_list

      post_query

      expect(upstreams_response.size).to eq(20)
      expect(list).to have_been_requested.once
    end
  end

  context 'when the repository is hosted or remote' do
    where(:kind) { %w[hosted remote] }

    with_them do
      let(:repository_body) { super().merge('kind' => kind) }

      it 'resolves the list null without asking Artifact Registry for upstreams', :aggregate_failures do
        stub_repository_read
        list = stub_upstreams_list

        post_query

        expect(upstreams_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(list).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the repository was deleted between the two reads (404 on the list)' do
    before do
      stub_upstreams_list(status: 404, body: error_envelope(code: 'not_found').to_json)
    end

    it_behaves_like 'resolving the list null while the repository still renders'
  end

  context 'when Artifact Registry answers the list read with a server error' do
    before do
      stub_upstreams_list(status: 503, body: error_envelope(code: 'service_unavailable').to_json)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read fails in transport' do
    before do
      stub_request(:get, upstreams_url).to_raise(Faraday::ConnectionFailed)
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when the list read times out' do
    before do
      stub_request(:get, upstreams_url).to_timeout
    end

    it_behaves_like 'rendering the service-unavailable error beside the loaded repository'
  end

  context 'when Artifact Registry breaches the kind contract on an upstream' do
    where(:scenario, :kind_attributes, :reported) do
      [
        ['a kind outside the contract', { 'kind' => 'virtual' }, 'virtual'],
        ['a null kind', { 'kind' => nil }, 'none'],
        ['a blank kind', { 'kind' => '' }, 'none'],
        ['no kind at all', {}, 'none']
      ]
    end

    with_them do
      let(:first_upstream) do
        association = super()
        summary = association['upstream_repository'].except('kind').merge(kind_attributes)

        association.merge('upstream_repository' => summary)
      end

      it 'nulls that row kind with a top-level error and keeps the list and repository', :aggregate_failures do
        stub_repository_read
        stub_upstreams_list

        post_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(repository_response['name']).to eq(repository_name)
        expect(upstreams_response).to be_present
        expect(upstreams_response.map { |row| row['upstreamRepository']['kind'] })
          .to contain_exactly(nil, 'REMOTE')
        expect_graphql_errors_to_include("unsupported upstream kind: #{reported}")
      end
    end
  end

  # Aliases would otherwise let one operation resolve the list repeatedly on the same repository,
  # each resolution its own Artifact Registry request. `FieldCallCount` raises on the second before
  # its resolve body runs, so the operation costs one list read rather than two.
  context 'when one operation selects the list twice under aliases' do
    let(:aliased_query) do
      <<~QUERY
        query {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              name
              a: upstreamRepositories { id }
              b: upstreamRepositories { id }
            }
          }
        }
      QUERY
    end

    it 'rejects the second selection and issues one list read, not two', :aggregate_failures do
      stub_repository_read
      list = stub_upstreams_list

      post_graphql(aliased_query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect_graphql_errors_to_include(/can be requested only for 1/)
      expect(list).to have_been_requested.once
    end
  end

  context 'when the list read renders without leaking the Artifact Registry credential' do
    it 'keeps the token and scheme out of the response body', :aggregate_failures do
      stub_repository_read
      stub_upstreams_list

      post_query

      expect(upstreams_response.pluck('position')).to eq([1, 2])
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      list = stub_upstreams_list

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(list).not_to have_been_requested
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the user is not a member of the organization' do
    let(:current_user) { non_member }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_upstreams_list(status: 200, body: upstreams_body.to_json, headers: json_headers)
    stub_request(:get, upstreams_url).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def upstreams_response
    repository_response&.dig('upstreamRepositories')
  end
end
