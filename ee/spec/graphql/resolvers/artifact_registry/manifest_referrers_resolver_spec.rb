# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::ManifestReferrersResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
  let(:digest) { "sha256:#{'1' * 64}" }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format) }
  let(:manifest) do
    ArtifactRegistry::ManifestDetail.new('id' => 'm1000-0000-0000-0000-000000000000', 'digest' => digest)
  end

  # The resolver hangs off the manifest detail element, so its object is the presenter that carries
  # the image id and digest the referrers read is keyed on.
  let(:presented_manifest) do
    ArtifactRegistry::ManifestPresenter.new(
      manifest, repository: repository, organization: organization, image_id: image_id
    )
  end

  let(:referrer) { ArtifactRegistry::Manifest.new('id' => 'r1000', 'digest' => "sha256:#{'a' * 64}") }
  let(:page) { ArtifactRegistry::Page.new(nodes: [referrer], next_cursor: 'next', prev_cursor: 'prev') }
  let(:client) { instance_double(ArtifactRegistry::Client, manifest_referrers: page) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }
  let(:args) { {} }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_referrers) do
    resolve(
      described_class,
      obj: presented_manifest,
      args: args,
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] }
    )
  end

  it 'returns the unwidened manifest element connection, nullable so a failed read hides it',
    :aggregate_failures do
    expect(described_class.type.unwrap.graphql_name).to eq('ArtifactRegistryManifestConnection')
    expect(described_class.type.non_null?).to be(false)
  end

  it 'limits the field to one resolution per operation, its own budget separate from the manifest' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  it 'reads the referrers off the presenter context, with both the image id and the digest',
    :aggregate_failures do
    resolve_referrers

    expect(client).to have_received(:manifest_referrers)
      .with(a_hash_including(
        slug: slug, repository_name: repository_name, format: format, image_id: image_id, digest: digest
      ))
  end

  it 'returns the referrer rows as an externally paginated connection', :aggregate_failures do
    result = resolve_referrers

    expect(result).to be_a(::Gitlab::Graphql::Pagination::ExternallyPaginatedArrayConnection)
    expect(result.nodes).to eq([referrer])
  end

  context 'when the repository is an OCI repository' do
    let(:format) { 'oci' }

    it "sends the repository's own format segment rather than inferring one" do
      resolve_referrers

      expect(client).to have_received(:manifest_referrers).with(a_hash_including(format: 'oci'))
    end
  end

  context 'when Artifact Registry answers 404 (manifest gone or remote empty)' do
    let(:client) { instance_double(ArtifactRegistry::Client, manifest_referrers: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_referrers).to be_nil
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_referrers).to be_nil
      expect(client).not_to have_received(:manifest_referrers)
    end
  end
end
