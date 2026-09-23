# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::ManifestResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
  let(:digest) { "sha256:#{'1' * 64}" }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format) }
  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: organization) }
  let(:manifest) do
    ArtifactRegistry::ManifestDetail.new(
      'id' => 'm1000-0000-0000-0000-000000000000', 'digest' => digest,
      'media_type' => 'application/vnd.oci.image.index.v1+json'
    )
  end

  let(:client) { instance_double(ArtifactRegistry::Client, manifest: manifest) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }
  let(:args) { { artifact_id: image_id, digest: digest } }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_manifest) do
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

  it 'reads the manifest through the organization the presenter carries, with the image ID and digest' do
    resolve_manifest

    expect(client).to have_received(:manifest)
      .with(slug: slug, repository_name: repository_name, format: format, image_id: image_id, digest: digest)
  end

  it 'wraps the manifest in a ManifestPresenter carrying the repository, organization, and image ID',
    :aggregate_failures do
    result = resolve_manifest

    expect(result).to be_a(::ArtifactRegistry::ManifestPresenter)
    expect(result.digest).to eq(digest)
    expect(result.repository).to eq(presented_repository)
    expect(result.organization).to eq(organization)
    # The image ID renders nowhere on this type; the referrers connection reads it off the
    # presenter, so pin the handoff here where a wrong value would otherwise surface a step later.
    expect(result.image_id).to eq(image_id)
  end

  context 'when the repository is an OCI repository' do
    let(:format) { 'oci' }

    it "sends the repository's own format segment rather than inferring one" do
      resolve_manifest

      expect(client).to have_received(:manifest).with(hash_including(format: 'oci'))
    end
  end

  context 'when Artifact Registry answers 404 (missing or forbidden)' do
    let(:client) { instance_double(ArtifactRegistry::Client, manifest: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_manifest).to be_nil
    end
  end

  context 'when the repository holds packages rather than images' do
    where(:format) { %w[maven npm] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_manifest).to be_nil
        expect(client).not_to have_received(:manifest)
      end
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_manifest).to be_nil
      expect(client).not_to have_received(:manifest)
    end
  end
end
