# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::VersionResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'maven' }
  let(:repository_name) { 'maven-releases' }
  let(:version_id) { 'v1000000-0000-0000-0000-000000000000' }
  let(:artifact_id) { 'p1000000-0000-0000-0000-000000000000' }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format) }
  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: organization) }
  let(:version) { ArtifactRegistry::Version.new('id' => version_id, 'package_id' => artifact_id) }
  let(:client) { instance_double(ArtifactRegistry::Client, version: version) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }
  let(:args) { { id: version_id, artifact_id: artifact_id } }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_version) do
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

  it 'reads the version through the organization the presenter carries, by version ID' do
    resolve_version

    expect(client).to have_received(:version)
      .with(slug: slug, repository_name: repository_name, format: format, version_id: version_id)
  end

  it 'wraps the resolved version in a VersionPresenter carrying the repository and organization',
    :aggregate_failures do
    result = resolve_version

    expect(result).to be_a(::ArtifactRegistry::VersionPresenter)
    expect(result.id).to eq(version_id)
    expect(result.repository).to eq(presented_repository)
    expect(result.organization).to eq(organization)
  end

  context 'when the repository holds npm packages' do
    let(:format) { 'npm' }

    it "sends the repository's own format segment rather than inferring one" do
      resolve_version

      expect(client).to have_received(:version).with(hash_including(format: 'npm'))
    end
  end

  context 'when Artifact Registry answers 404 (missing or forbidden)' do
    let(:client) { instance_double(ArtifactRegistry::Client, version: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_version).to be_nil
    end
  end

  describe 'the artifact pairing check' do
    context 'when the version belongs to a different package' do
      let(:version) { ArtifactRegistry::Version.new('id' => version_id, 'package_id' => 'other-package-id') }

      it 'resolves null, so a mismatched deep link renders the not-found state' do
        expect(resolve_version).to be_nil
      end
    end

    context 'when Artifact Registry omits package_id (the pre-serialization path)' do
      let(:version) { ArtifactRegistry::Version.new('id' => version_id) }

      it 'fails open and resolves the version, rather than nulling every version' do
        expect(resolve_version).to be_a(::ArtifactRegistry::VersionPresenter)
      end
    end

    context 'when Artifact Registry serializes a matching package_id as a JSON number' do
      let(:artifact_id) { '123' }
      let(:version) { ArtifactRegistry::Version.new('id' => version_id, 'package_id' => 123) }

      it 'resolves the version rather than failing the pairing check on the raw numeric value' do
        expect(resolve_version).to be_a(::ArtifactRegistry::VersionPresenter)
      end
    end
  end

  context 'when the repository holds images rather than packages' do
    where(:format) { %w[docker oci] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_version).to be_nil
        expect(client).not_to have_received(:version)
      end
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_version).to be_nil
      expect(client).not_to have_received(:version)
    end
  end
end
