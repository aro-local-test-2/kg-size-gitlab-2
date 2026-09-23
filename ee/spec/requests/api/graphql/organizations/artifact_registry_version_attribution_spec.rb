# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry version publish attribution', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_user) { create(:organization_user, organization: organization).user }
  let_it_be(:creator) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:token) { 'ar-request-spec-credential' }
  let(:slug) { 'resolved-handle' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:current_user) { organization_user }
  let(:format) { 'maven' }
  let(:package_fragment) { 'ArtifactRegistryMavenPackage' }
  let(:repository_name) { 'maven-releases' }
  let(:package_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }
  let(:sha) { 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' }
  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{repository_name}" }
  let(:packages_url) { "#{repository_url}/#{format}/packages" }
  let(:versions_url) { "#{packages_url}/#{package_id}/versions" }

  let(:repository_body) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => repository_name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'downloads_count' => 0,
      'size_bytes' => 0,
      'settings' => {}
    }
  end

  let(:package_row) { { 'id' => package_id, 'group_id' => 'com.example.tools', 'artifact_id' => 'payment-core' } }
  let(:version_row) do
    {
      'id' => 'v1000-0000-0000-0000-000000000000',
      'version' => '1.10.0',
      'created_at' => '2026-07-03T09:15:00Z',
      'created_by' => creator.id.to_s,
      'project_id' => project.id.to_s,
      'git_commit_sha' => sha
    }
  end

  let(:versions_body) { [version_row] }

  let(:query) do
    <<~QUERY
      query organizationArtifactRegistryVersionAttribution($id: OrganizationsOrganizationID!, $name: String!) {
        organization(id: $id) {
          artifactRegistryRepository(name: $name) {
            packages(first: 20) {
              nodes {
                __typename
                ... on #{package_fragment} {
                  versions(first: 20) {
                    nodes {
                      id
                      createdBy { id username }
                      project { id fullPath }
                      commitSha
                      commitPath
                    }
                  }
                }
              }
            }
          }
        }
      }
    QUERY
  end

  before_all do
    project.add_developer(organization_user)
  end

  include_context 'with a resolved Artifact Registry handle'

  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return(token)
    end

    stub_repository_read
    stub_packages_list
    stub_versions_list
  end

  subject(:post_query) do
    post_graphql(query, current_user: current_user,
      variables: { id: organization.to_global_id.to_s, name: repository_name })
  end

  def stub_repository_read
    stub_request(:get, repository_url).to_return(status: 200, body: repository_body.to_json, headers: json_headers)
  end

  def stub_packages_list
    stub_request(:get, packages_url).with(query: { limit: '20' })
      .to_return(status: 200, body: [package_row].to_json, headers: json_headers)
  end

  def stub_versions_list(body: versions_body.to_json)
    stub_request(:get, versions_url).with(query: { limit: '20', sort: 'created_at', order: 'desc' })
      .to_return(status: 200, body: body, headers: json_headers)
  end

  def attribution_nodes
    graphql_dig_at(graphql_data, :organization, :artifact_registry_repository, :packages, :nodes)
      .first['versions']['nodes']
  end

  # The Maven and npm resolvers are shared, so a mismatch would surface on either. The npm read
  # routes through the same package/versions URL shape.
  context 'when the creator and project resolve and the viewer can see them' do
    where(:format, :repository_name, :package_fragment) do
      'maven' | 'maven-releases' | 'ArtifactRegistryMavenPackage'
      'npm'   | 'npm-releases'   | 'ArtifactRegistryNpmPackage'
    end

    with_them do
      let(:package_row) do
        format == 'npm' ? { 'id' => package_id, 'name' => '@acme/ui', 'scope' => '@acme' } : super()
      end

      it 'renders the creator, project, raw SHA, and a project-derived commit path',
        :aggregate_failures do
        post_query

        node = attribution_nodes.first
        expect(node['createdBy']['id']).to eq(creator.to_global_id.to_s)
        expect(node['project']['fullPath']).to eq(project.full_path)
        expect(node['commitSha']).to eq(sha)
        expect(node['commitPath']).to eq(project_commit_path(project, sha))
        expect(graphql_errors).to be_nil
      end
    end
  end

  describe 'batching and repository reads' do
    let_it_be(:creators) { create_list(:user, 3) }
    let_it_be(:projects) { create_list(:project, 3) }

    let(:versions_body) do
      creators.each_index.map do |i|
        {
          'id' => "v#{i}",
          'version' => "1.#{i}.0",
          'created_at' => '2026-07-03T09:15:00Z',
          'created_by' => creators[i].id.to_s,
          'project_id' => projects[i].id.to_s,
          'git_commit_sha' => sha
        }
      end
    end

    before_all do
      projects.each { |p| p.add_developer(organization_user) }
    end

    # Distinct references per row prove the batch joins the whole page with one query per
    # referenced type, not one per row, and no per-row repository read. project_features is
    # preloaded with the projects, so the read_code gate adds no per-project feature query.
    it 'joins the whole page through one users, projects, and project_features query',
      :aggregate_failures do
      recorder = ActiveRecord::QueryRecorder.new { post_query }

      expect(graphql_errors).to be_nil
      expect(recorder.log.grep(/FROM "users"/).size).to eq(1)
      expect(recorder.log.grep(/FROM "projects"/).size).to eq(1)
      expect(recorder.log.grep(/FROM "project_features"/).size).to eq(1)

      nodes = attribution_nodes
      expect(nodes.map { |n| n.dig('createdBy', 'id') })
        .to eq(creators.map { |u| u.to_global_id.to_s })
      expect(nodes.map { |n| n.dig('project', 'fullPath') }).to eq(projects.map(&:full_path))
    end

    it 'reads Artifact Registry without touching Gitaly, since the join reads no repository' do
      expect { post_query }.not_to change { Gitlab::GitalyClient.get_request_count }
    end
  end

  context 'when the creator reference is null' do
    let(:version_row) { super().merge('created_by' => nil) }

    it 'renders a null creator while the project, SHA, and commit path still resolve',
      :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['createdBy']).to be_nil
      expect(node['project']['fullPath']).to eq(project.full_path)
      expect(node['commitSha']).to eq(sha)
      expect(node['commitPath']).to eq(project_commit_path(project, sha))
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the creator reference does not resolve to a user' do
    let(:version_row) { super().merge('created_by' => non_existing_record_id.to_s) }

    it 'renders a null creator while the rest of the row still resolves', :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['createdBy']).to be_nil
      expect(node['project']['fullPath']).to eq(project.full_path)
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the project reference is null' do
    let(:version_row) { super().merge('project_id' => nil) }

    it 'renders a null project, SHA, and commit path, since both commit fields need the project',
      :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['project']).to be_nil
      expect(node['commitPath']).to be_nil
      expect(node['commitSha']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the project reference does not resolve' do
    let(:version_row) { super().merge('project_id' => non_existing_record_id.to_s) }

    it 'renders a null project, SHA, and commit path', :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['project']).to be_nil
      expect(node['commitPath']).to be_nil
      expect(node['commitSha']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the viewer cannot see the referenced project' do
    # Not a member of this private project, so ProjectType's own authorization hides it. Both
    # commit fields route through that same decision, so neither the path nor the SHA leaks a
    # commit identifier of a project the viewer cannot access.
    let_it_be(:other_project) { create(:project, :private) }

    let(:version_row) { super().merge('project_id' => other_project.id.to_s) }

    it 'renders a null project, commit path, and SHA (existence-hiding on the join)',
      :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['project']).to be_nil
      expect(node['commitPath']).to be_nil
      expect(node['commitSha']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the viewer can see the project but cannot read its code' do
    # A commit SHA and its path are repository content: both are null unless the viewer can
    # read the code, not merely see the project. Guest can see a private project but not its code.
    let_it_be(:code_gated_project) { create(:project, :private) }

    let(:version_row) { super().merge('project_id' => code_gated_project.id.to_s) }

    before_all do
      code_gated_project.add_guest(organization_user)
    end

    it 'renders the project but null commit SHA and path', :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['project']['fullPath']).to eq(code_gated_project.full_path)
      expect(node['commitSha']).to be_nil
      expect(node['commitPath']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the SHA is malformed or out of the route-admissible range' do
    # AR types the SHA as an opaque value, so it can arrive malformed. The commit route admits
    # only `\h{7,64}`, so an unguarded value would 500 the query. The table walks both near
    # misses of the length window ('a' * 6 and 'a' * 65) plus non-hex and empty inputs.
    where(:malformed_sha) { ['', 'nothex!', 'a' * 6, 'g' * 40, 'a' * 65] }

    with_them do
      let(:version_row) { super().merge('git_commit_sha' => malformed_sha) }

      it 'renders null commit SHA and path rather than raising', :aggregate_failures do
        post_query

        node = attribution_nodes.first
        expect(node['commitSha']).to be_nil
        expect(node['commitPath']).to be_nil
        expect(node['project']['fullPath']).to eq(project.full_path)
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the SHA sits at a route-admissible boundary' do
    # The route window is `\h{7,64}`; the default sha exercises only the 40-char middle. These
    # lock in that both ends of the window render, so a future tightening cannot silently drop them.
    where(:boundary_sha) { ['a' * 7, 'a' * 64] }

    with_them do
      let(:version_row) { super().merge('git_commit_sha' => boundary_sha) }

      it 'renders both commit fields', :aggregate_failures do
        post_query

        node = attribution_nodes.first
        expect(node['commitSha']).to eq(boundary_sha)
        expect(node['commitPath']).to eq(project_commit_path(project, boundary_sha))
        expect(graphql_errors).to be_nil
      end
    end
  end

  context 'when the SHA is a non-string value that would stringify to hex' do
    # 1234567.to_s is "1234567", which matches the route pattern, so the is_a?(String) guard is
    # what keeps a non-string opaque value from rendering. Without it both commit fields would
    # render a nonsense SHA and a dead commit path (the read_code gate still blocks any leak).
    let(:version_row) { super().merge('git_commit_sha' => 1234567) }

    it 'renders null commit SHA and path', :aggregate_failures do
      post_query

      node = attribution_nodes.first
      expect(node['commitSha']).to be_nil
      expect(node['commitPath']).to be_nil
      expect(node['project']['fullPath']).to eq(project.full_path)
      expect(graphql_errors).to be_nil
    end
  end

  context 'when the creator reference is a non-numeric string' do
    # AR stores the reference as an opaque string, so a blank or non-numeric value is
    # representable. BatchModelLoader coerces through to_i, so each resolves a null creator.
    where(:bad_creator) { ['', 'abc'] }

    with_them do
      let(:version_row) { super().merge('created_by' => bad_creator) }

      it 'renders a null creator while the rest of the row resolves', :aggregate_failures do
        post_query

        node = attribution_nodes.first
        expect(node['createdBy']).to be_nil
        expect(node['project']['fullPath']).to eq(project.full_path)
        expect(graphql_errors).to be_nil
      end
    end
  end
end
