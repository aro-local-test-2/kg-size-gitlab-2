# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry single version', feature_category: :artifact_registry do
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
  let(:repository_name) { 'maven-releases' }
  let(:version_id) { 'v1000000-0000-0000-0000-000000000000' }
  let(:artifact_id) { 'p1000000-0000-0000-0000-000000000000' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:version_url) { "#{repository_url}/#{format}/versions/#{version_id}" }
  let(:statistics_url) { "#{version_url}/statistics" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'settings' => {}
    }
  end

  let(:version_body) do
    {
      'id' => version_id,
      'version' => '1.10.0',
      'created_at' => '2026-07-03T09:15:00Z',
      'size' => 9_876_543_210,
      'package_id' => artifact_id,
      'created_by' => nil,
      'project_id' => nil,
      'git_commit_sha' => nil
    }
  end

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryVersion(
        $id: OrganizationsOrganizationID!
        $name: String!
        $versionId: ID!
        $artifactId: ID!
      ) {
        organization(id: $id) {
          id
          artifactRegistryRepository(name: $name) {
            name
            version(id: $versionId, artifactId: $artifactId) {
              id
              version
              sizeBytes
              createdAt
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
      variables: { id: organization.to_global_id.to_s, name: repository_name,
                   versionId: version_id, artifactId: artifact_id })
  end

  shared_examples 'resolving the version for the repository format' do
    it 'renders the version fields, including the stored size', :aggregate_failures do
      stub_repository_read
      stub_version_read

      post_query

      expect(version_response).to eq(
        'id' => version_id,
        'version' => '1.10.0',
        'sizeBytes' => '9876543210',
        'createdAt' => '2026-07-03T09:15:00+00:00'
      )
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the version resolves for a Maven repository' do
    it_behaves_like 'resolving the version for the repository format'

    it 'issues one repository read and one version read, with no per-field follow-up',
      :aggregate_failures do
      repo = stub_repository_read
      version = stub_version_read

      post_query

      expect(repo).to have_been_requested.once
      expect(version).to have_been_requested.once
    end

    it 'renders the version without leaking the Artifact Registry credential', :aggregate_failures do
      stub_repository_read
      stub_version_read

      post_query

      expect(version_response['version']).to eq('1.10.0')
      expect(response.body).not_to include(token)
      expect(response.body.downcase).not_to include('bearer')
    end
  end

  context 'when the version resolves for an npm repository' do
    let(:format) { 'npm' }
    let(:repository_name) { 'npm-releases' }

    it_behaves_like 'resolving the version for the repository format'
  end

  describe 'the resolved publish attribution' do
    let_it_be(:project) { create(:project, :repository, organization: organization) }

    let(:version_body) do
      super().merge(
        'created_by' => organization_user.id.to_s,
        'project_id' => project.id.to_s,
        'git_commit_sha' => project.commit.sha
      )
    end

    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryVersionAttribution(
          $id: OrganizationsOrganizationID!
          $name: String!
          $versionId: ID!
          $artifactId: ID!
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              version(id: $versionId, artifactId: $artifactId) {
                id
                createdBy { username }
                project { fullPath }
                commitSha
                commitPath
              }
            }
          }
        }
      QUERY
    end

    before_all do
      project.add_developer(organization_user)
    end

    # Criterion 9 over the single-version read path: the attribution resolves through the new
    # VersionPresenter, the only new link in this object chain, rather than through the versions
    # connection the version-list slice covers.
    it 'resolves the publisher, project, and commit through the version field', :aggregate_failures do
      stub_repository_read
      stub_version_read

      post_query

      expect(version_response['createdBy']['username']).to eq(organization_user.username)
      expect(version_response['project']['fullPath']).to eq(project.full_path)
      expect(version_response['commitSha']).to eq(project.commit.sha)
      expect(version_response['commitPath']).to eq(project_commit_path(project, project.commit.sha))
      expect(graphql_errors).to be_nil
    end
  end

  describe 'the version statistics field' do
    let(:statistics_query) do
      <<~QUERY
        query organizationArtifactRegistryVersionStatistics(
          $id: OrganizationsOrganizationID!
          $name: String!
          $versionId: ID!
          $artifactId: ID!
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              version(id: $versionId, artifactId: $artifactId) {
                id
                statistics { filesCount }
              }
            }
          }
        }
      QUERY
    end

    subject(:post_statistics_query) do
      post_graphql(statistics_query, current_user: current_user,
        variables: { id: organization.to_global_id.to_s, name: repository_name,
                     versionId: version_id, artifactId: artifact_id })
    end

    context 'for a hosted package repository' do
      it 'renders the files count', :aggregate_failures do
        stub_repository_read
        stub_version_read
        stub_statistics_read(body: { 'files_count' => 12 }.to_json)

        post_statistics_query

        expect(version_response['statistics']).to eq('filesCount' => '12')
        expect(graphql_errors).to be_nil
      end

      it 'renders filesCount null when the response omits the count', :aggregate_failures do
        stub_repository_read
        stub_version_read
        stub_statistics_read(body: {}.to_json)

        post_statistics_query

        expect(version_response['statistics']).to eq('filesCount' => nil)
        expect(graphql_errors).to be_nil
      end
    end

    where(:status) { [404, 501] }

    with_them do
      context "when Artifact Registry answers the statistics read with #{params[:status]}" do
        it 'resolves the field null rather than raising, after issuing the read', :aggregate_failures do
          stub_repository_read
          stub_version_read
          statistics = stub_statistics_read(status: status, body: error_envelope(code: 'not_found').to_json)

          post_statistics_query

          expect(version_response['id']).to eq(version_id)
          expect(version_response['statistics']).to be_nil
          expect(statistics).to have_been_requested.once
          expect(graphql_errors).to be_nil
        end
      end
    end

    context 'when the statistics read is rejected with 401 or 403' do
      where(:status) { [401, 403] }

      with_them do
        it 'resolves the field null silently, beside the rendered version', :aggregate_failures do
          stub_repository_read
          stub_version_read
          stub_statistics_read(status: status, body: error_envelope(code: 'denied').to_json)

          post_statistics_query

          expect(version_response['id']).to eq(version_id)
          expect(version_response['statistics']).to be_nil
          expect(graphql_errors).to be_nil
        end
      end
    end

    context 'when the statistics read is unavailable (5xx)' do
      it 'renders the service-unavailable error beside the version, with request_id preserved',
        :aggregate_failures do
        stub_repository_read
        stub_version_read
        stub_statistics_read(status: 503, body: error_envelope(code: 'unavailable', request_id: 'req-503').to_json)

        post_statistics_query

        expect(version_response['statistics']).to be_nil
        expect(version_response['id']).to eq(version_id)
        expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
        expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-503')
      end
    end

    context 'when the statistics read fails in transport' do
      it 'renders the service-unavailable error on a connection failure' do
        stub_repository_read
        stub_version_read
        stub_request(:get, statistics_url).to_raise(Faraday::ConnectionFailed)

        post_statistics_query

        expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      end
    end

    context 'when the statistics read returns a non-404 client error' do
      it 'surfaces a top-level error carrying the request_id, not a bare null', :aggregate_failures do
        stub_repository_read
        stub_version_read
        stub_statistics_read(status: 422, body: error_envelope(code: 'unprocessable', request_id: 'req-422').to_json)

        post_statistics_query

        expect(graphql_errors).to be_present
        expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-422')
      end
    end

    context 'on a remote repository (statistics are hosted-only)' do
      let(:repository_body) { super().merge('kind' => 'remote') }

      it 'resolves the field null without reading statistics from Artifact Registry',
        :aggregate_failures do
        stub_repository_read
        stub_version_read
        statistics = stub_request(:get, statistics_url)

        post_statistics_query

        expect(version_response['statistics']).to be_nil
        expect(statistics).not_to have_been_requested
        expect(graphql_errors).to be_nil
      end
    end

    context 'when the statistics field is selected twice in one operation' do
      let(:statistics_query) do
        <<~QUERY
          query organizationArtifactRegistryVersionStatisticsAliased(
            $id: OrganizationsOrganizationID!, $name: String!, $versionId: ID!, $artifactId: ID!
          ) {
            organization(id: $id) {
              artifactRegistryRepository(name: $name) {
                version(id: $versionId, artifactId: $artifactId) {
                  statistics { filesCount }
                  second: statistics { filesCount }
                }
              }
            }
          }
        QUERY
      end

      it 'raises the call-count limit rather than issuing a second statistics read',
        :aggregate_failures do
        stub_repository_read
        stub_version_read
        statistics = stub_statistics_read(body: { 'files_count' => 12 }.to_json)

        post_statistics_query

        expect_graphql_errors_to_include(/can be requested only for 1/)
        expect(statistics).to have_been_requested.once
      end
    end

    # FieldCallCount keys per operation, so a multiplex gets the budget per operation while the
    # repository read still coalesces across the request (criterion 31, statistics half).
    context 'when a multiplex carries the same statistics selection in two operations' do
      let(:multiplex_query) do
        <<~QUERY
          query OPERATION_NAME {
            organization(id: "#{organization.to_global_id}") {
              id
              artifactRegistryRepository(name: "#{repository_name}") {
                version(id: "#{version_id}", artifactId: "#{artifact_id}") { statistics { filesCount } }
              }
            }
          }
        QUERY
      end

      it 'budgets the statistics field per operation and reads the repository once', :aggregate_failures do
        detail = stub_repository_read
        stub_version_read
        statistics = stub_statistics_read(body: { 'files_count' => 12 }.to_json)

        post_multiplex(
          [
            { query: multiplex_query.sub('OPERATION_NAME', 'first_operation') },
            { query: multiplex_query.sub('OPERATION_NAME', 'second_operation') }
          ],
          current_user: current_user
        )

        expect(response).to have_gitlab_http_status(:ok)
        expect(detail).to have_been_requested.once
        expect(statistics).to have_been_requested.twice
        expect(json_response.pluck('errors').flatten.compact).to be_empty
      end
    end
  end

  # 404, 401, and 403 all take the existence-hiding arm: the field resolves null and the
  # repository still renders, so a missing version and a forbidden one are indistinguishable.
  [404, 401, 403].each do |status|
    context "when Artifact Registry answers the version read with #{status}" do
      it 'resolves the version null, no error, and the repository around it', :aggregate_failures do
        stub_repository_read
        stub_version_read(status: status, body: error_envelope(code: 'not_found').to_json)

        post_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(version_response).to be_nil
        expect(repository_response['name']).to eq(repository_name)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the version belongs to a different package' do
    let(:version_body) { super().merge('package_id' => 'a-different-package-id') }

    it 'resolves null, so a mismatched deep link renders the not-found state', :aggregate_failures do
      stub_repository_read
      stub_version_read

      post_query

      expect(version_response).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when Artifact Registry omits package_id (the pre-serialization path)' do
    let(:version_body) { super().except('package_id') }

    it 'fails open and renders the version rather than nulling it', :aggregate_failures do
      stub_repository_read
      stub_version_read

      post_query

      expect(version_response['id']).to eq(version_id)
      expect(graphql_errors).to be_nil
    end
  end

  context 'when Artifact Registry stores no size' do
    let(:version_body) { super().merge('size' => nil) }

    it 'resolves sizeBytes null rather than fabricating a zero', :aggregate_failures do
      stub_repository_read
      stub_version_read

      post_query

      expect(version_response['sizeBytes']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the repository holds images rather than packages' do
    where(:format, :repository_name) do
      'docker' | 'container-images'
      'oci'    | 'oci-artifacts'
    end

    with_them do
      it 'resolves null without reading the version, and emits no error', :aggregate_failures do
        stub_repository_read
        version = stub_request(:get, version_url)

        post_query

        expect(version_response).to be_nil
        expect(version).not_to have_been_requested
        expect(repository_response['name']).to eq(repository_name)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when Artifact Registry is unavailable (5xx)' do
    it 'renders the service-unavailable error beside the loaded repository, with request_id preserved',
      :aggregate_failures do
      stub_repository_read
      stub_version_read(status: 503,
        body: error_envelope(code: 'unavailable', request_id: 'req-503').to_json)

      post_query

      expect(version_response).to be_nil
      expect(repository_response['name']).to eq(repository_name)
      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-503')
    end
  end

  context 'when Artifact Registry answers the version read with a non-404 client error' do
    it 'surfaces a top-level error carrying the request_id, not a bare null', :aggregate_failures do
      stub_repository_read
      stub_version_read(status: 422,
        body: error_envelope(code: 'unprocessable', request_id: 'req-422').to_json)

      post_query

      expect(graphql_errors).to be_present
      expect(graphql_errors.first.dig('extensions', 'request_id')).to eq('req-422')
    end
  end

  context 'when the version read fails in transport' do
    it 'renders the service-unavailable error on a connection failure' do
      stub_repository_read
      stub_request(:get, version_url).to_raise(Faraday::ConnectionFailed)

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end

    it 'renders the service-unavailable error on a timeout, which the retry middleware handles' do
      stub_repository_read
      stub_request(:get, version_url).to_timeout

      post_query

      expect_graphql_errors_to_include('The Artifact Registry service is unavailable.')
    end
  end

  shared_examples 'hiding the repository without reaching Artifact Registry' do
    it 'renders a null repository and no error, and builds no client', :aggregate_failures do
      detail = stub_repository_read
      version = stub_request(:get, version_url)

      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_query

      expect(repository_response).to be_nil
      expect(detail).not_to have_been_requested
      expect(version).not_to have_been_requested
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

  # The anonymous caller takes a distinct path through the client's service-credential branch
  # and CachesClient memoization; the no-existence-leak guarantee must hold for it too.
  context 'when the caller is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'hiding the repository without reaching Artifact Registry'
  end

  context 'when the version field is selected twice in one operation' do
    let(:query) do
      <<~QUERY
        query organizationArtifactRegistryVersionAliased(
          $id: OrganizationsOrganizationID!
          $name: String!
          $versionId: ID!
          $artifactId: ID!
        ) {
          organization(id: $id) {
            artifactRegistryRepository(name: $name) {
              version(id: $versionId, artifactId: $artifactId) { id }
              second: version(id: $versionId, artifactId: $artifactId) { id }
            }
          }
        }
      QUERY
    end

    it 'raises the call-count limit rather than issuing a second version read', :aggregate_failures do
      stub_repository_read
      version = stub_version_read

      post_query

      expect_graphql_errors_to_include(/can be requested only for 1/)
      # The first selection reads once; the limit blocks the second from issuing another read.
      expect(version).to have_been_requested.once
    end
  end

  # `FieldCallCount` keys on the operation fingerprint, so a multiplex gets the budget per
  # operation rather than once overall, while the repository read still coalesces across the
  # request. Plan Step 5 pins this: "the limit counted per operation so a multiplex keeps a
  # budget per operation."
  context 'when a multiplex carries the same version selection in two operations' do
    let(:multiplex_query) do
      <<~QUERY
        query OPERATION_NAME {
          organization(id: "#{organization.to_global_id}") {
            id
            artifactRegistryRepository(name: "#{repository_name}") {
              version(id: "#{version_id}", artifactId: "#{artifact_id}") { id }
            }
          }
        }
      QUERY
    end

    it 'budgets the version field per operation and reads the repository once', :aggregate_failures do
      detail = stub_repository_read
      version = stub_version_read

      post_multiplex(
        [
          { query: multiplex_query.sub('OPERATION_NAME', 'first_operation') },
          { query: multiplex_query.sub('OPERATION_NAME', 'second_operation') }
        ],
        current_user: current_user
      )

      expect(response).to have_gitlab_http_status(:ok)
      expect(detail).to have_been_requested.once
      expect(version).to have_been_requested.twice
      expect(json_response.pluck('errors').flatten.compact).to be_empty
    end
  end

  def stub_repository_read(status: 200, body: repository_body.to_json, headers: json_headers)
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_version_read(status: 200, body: version_body.to_json, headers: json_headers)
    stub_request(:get, version_url).to_return(status: status, body: body, headers: headers)
  end

  def stub_statistics_read(status: 200, body: {}.to_json, headers: json_headers)
    stub_request(:get, statistics_url).to_return(status: status, body: body, headers: headers)
  end

  def error_envelope(code:, message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_response
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository)
  end

  def version_response
    repository_response&.dig('version')
  end
end
