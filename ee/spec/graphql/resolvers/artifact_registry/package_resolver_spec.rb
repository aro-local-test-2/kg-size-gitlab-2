# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::PackageResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-releases' }
  let(:artifact_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format) }
  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: organization) }
  let(:artifact) { ArtifactRegistry::MavenPackage.new('id' => artifact_id) }
  let(:client) { instance_double(ArtifactRegistry::Client, package: artifact) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }
  let(:args) { { id: artifact_id } }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_package) do
    resolve(
      described_class,
      obj: presented_repository,
      args: args,
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] }
    )
  end

  it 'limits the field to one resolution per request, ahead of any client call' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  it 'returns the package detail union' do
    expect(described_class.type.unwrap.graphql_name).to eq('ArtifactRegistryPackageDetails')
  end

  it 'reads the package through the organization the presenter carries, with the artifact ID' do
    resolve_package

    expect(client).to have_received(:package)
      .with(slug: slug, repository_name: repository_name, format: format, id: artifact_id)
  end

  it 'wraps the resolved package in an ArtifactPresenter carrying the repository and organization',
    :aggregate_failures do
    result = resolve_package

    expect(result).to be_a(::ArtifactRegistry::ArtifactPresenter)
    expect(result.id).to eq(artifact_id)
    expect(result.repository).to eq(presented_repository)
    expect(result.organization).to eq(organization)
  end

  context 'when the repository holds npm packages' do
    let(:format) { 'npm' }
    let(:artifact) { ArtifactRegistry::NpmPackage.new('id' => artifact_id) }

    it "sends the repository's own format segment rather than inferring one" do
      resolve_package

      expect(client).to have_received(:package).with(hash_including(format: 'npm'))
    end
  end

  context 'when Artifact Registry answers 404 (missing or forbidden)' do
    let(:client) { instance_double(ArtifactRegistry::Client, package: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_package).to be_nil
    end
  end

  context 'when the repository holds images rather than packages' do
    where(:format) { %w[docker oci] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_package).to be_nil
        expect(client).not_to have_received(:package)
      end
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_package).to be_nil
      expect(client).not_to have_received(:package)
    end
  end
end
