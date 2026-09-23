# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::NpmDistTagsResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'npm' }
  let(:kind) { 'hosted' }
  let(:repository_name) { 'npm-releases' }
  let(:package_id) { 'p1000000-0000-0000-0000-000000000000' }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format, 'kind' => kind) }
  let(:package) { ArtifactRegistry::NpmPackage.new('id' => package_id) }
  let(:presented_artifact) { ArtifactRegistry::ArtifactPresenter.new(package, repository: repository, organization: organization) }
  let(:dist_tag) { ArtifactRegistry::NpmDistTag.new('id' => 't1', 'name' => 'latest', 'version_id' => 'v1', 'version' => '1.10.0') }
  let(:page) { ArtifactRegistry::Page.new(nodes: [dist_tag]) }
  let(:client) { instance_double(ArtifactRegistry::Client, npm_dist_tags: page) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_dist_tags) do
    resolve(
      described_class,
      obj: presented_artifact,
      args: {},
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] }
    )
  end

  it 'limits the field to one resolution per request, ahead of any client call' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  it 'reads the dist-tags through the organization the presenter carries, by package ID' do
    resolve_dist_tags

    expect(client).to have_received(:npm_dist_tags)
      .with(hash_including(slug: slug, repository_name: repository_name, package_id: package_id))
  end

  context 'when the repository is remote (Artifact Registry serves no dist-tag rows)' do
    let(:kind) { 'remote' }

    it 'resolves null without reaching Artifact Registry, matching the delete mutation',
      :aggregate_failures do
      expect(resolve_dist_tags).to be_nil
      expect(client).not_to have_received(:npm_dist_tags)
    end
  end

  context 'when the repository is virtual (allowed, as the delete mutation allows it)' do
    let(:kind) { 'virtual' }

    it 'reads the dist-tags rather than refusing the repository' do
      resolve_dist_tags

      expect(client).to have_received(:npm_dist_tags)
    end
  end

  context 'when the repository is a Maven repository' do
    let(:format) { 'maven' }
    let(:package) { ArtifactRegistry::MavenPackage.new('id' => package_id) }

    it 'resolves null without reaching Artifact Registry', :aggregate_failures do
      expect(resolve_dist_tags).to be_nil
      expect(client).not_to have_received(:npm_dist_tags)
    end
  end

  context 'when Artifact Registry answers 404 (missing package)' do
    let(:client) { instance_double(ArtifactRegistry::Client, npm_dist_tags: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_dist_tags).to be_nil
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_dist_tags).to be_nil
      expect(client).not_to have_received(:npm_dist_tags)
    end
  end
end
