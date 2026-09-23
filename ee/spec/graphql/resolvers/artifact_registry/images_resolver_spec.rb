# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::ImagesResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'docker' }
  let(:repository_name) { 'container-images' }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format) }
  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: organization) }
  let(:page) { ArtifactRegistry::Page.new(nodes: []) }
  let(:client) { instance_double(ArtifactRegistry::Client, images: page) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }
  # The schema default, not the field's `max_page_size: 20`. `resolve` forwards only
  # `calls_gitaly` and `connection_extension` to the field it builds, so no cap reaches it. The
  # real cap is asserted on the field in the detail type spec, and over the wire in
  # ee/spec/requests/api/graphql/organizations/artifact_registry_repository_images_spec.rb.
  let(:schema_default_page_size) { GitlabSchema.default_max_page_size }
  let(:args) { {} }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_images) do
    resolve(
      described_class,
      obj: presented_repository,
      args: args,
      # Mirrors the organization-rooted field's own mount. The field `resolve` builds inherits
      # no skip, and without one the redactor authorizes each image node -- which has no policy
      # class.
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] },
      field_opts: { connection_extension: ::Gitlab::Graphql::Extensions::ExternallyPaginatedArrayExtension }
    )
  end

  it 'limits the field to one resolution per request, ahead of any client call' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  it 'reads the repository the field hangs off through the organization the presenter carries' do
    resolve_images

    expect(client).to have_received(:images)
      .with(slug: slug, repository_name: repository_name, format: format, limit: schema_default_page_size)
  end

  context 'when the repository holds OCI images' do
    let(:format) { 'oci' }
    let(:repository_name) { 'oci-images' }

    it "sends the repository's own format segment rather than inferring one" do
      resolve_images

      expect(client).to have_received(:images)
        .with(slug: slug, repository_name: repository_name, format: 'oci', limit: schema_default_page_size)
    end
  end

  context 'with a requested page size below the maximum' do
    let(:args) { { first: 10 } }

    it 'forwards the requested size as the outbound limit' do
      resolve_images

      expect(client).to have_received(:images).with(hash_including(limit: 10))
    end
  end

  context 'with a requested page size above the maximum' do
    let(:args) { { first: GitlabSchema.default_max_page_size + 1 } }

    it 'caps the outbound limit at the maximum' do
      resolve_images

      expect(client).to have_received(:images).with(hash_including(limit: schema_default_page_size))
    end
  end

  context 'when paging forward' do
    let(:args) { { first: 10, after: 'NEXT_CURSOR' } }

    it 'forwards the forward cursor' do
      resolve_images

      expect(client).to have_received(:images).with(hash_including(limit: 10, cursor: 'NEXT_CURSOR'))
    end
  end

  context 'when paging backward' do
    let(:args) { { last: 5, before: 'PREV_CURSOR' } }

    it 'forwards the backward cursor' do
      resolve_images

      expect(client).to have_received(:images).with(hash_including(limit: 5, cursor: 'PREV_CURSOR'))
    end
  end

  it 'sends no cursor on the first page' do
    resolve_images

    expect(client).to have_received(:images).with(hash_not_including(:cursor))
  end

  describe 'the resolved connection' do
    let(:image) { ArtifactRegistry::Image.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000', 'name' => 'alpha') }
    let(:other_image) { ArtifactRegistry::Image.new('id' => 'b2c3d4e5-0000-0000-0000-000000000000', 'name' => 'beta') }
    let(:page) do
      ArtifactRegistry::Page.new(
        nodes: [image, other_image],
        next_cursor: 'NEXT_CURSOR',
        prev_cursor: 'PREV_CURSOR'
      )
    end

    # `eq`, not `match_array`: Artifact Registry sorts by name and the resolver passes the page
    # straight through, so a reordering is a defect an order-free assertion could not see.
    it 'carries the rows in order, and both Link-header cursors the client parsed',
      :aggregate_failures do
      connection = resolve_images

      expect(connection.nodes).to eq([image, other_image])
      expect(connection.start_cursor).to eq('PREV_CURSOR')
      expect(connection.end_cursor).to eq('NEXT_CURSOR')
      expect(connection.has_next_page).to be(true)
      expect(connection.has_previous_page).to be(true)
    end

    # `eq` above passes with or without the wrap, since ArtifactPresenter is a SimpleDelegator;
    # this pins that the manifests connection mounted on the image type reaches its context.
    it 'wraps each row in an ArtifactPresenter carrying the repository and organization',
      :aggregate_failures do
      connection = resolve_images

      expect(connection.nodes).to all(be_a(::ArtifactRegistry::ArtifactPresenter))
      expect(connection.nodes.map(&:id)).to eq(
        %w[a1b2c3d4-0000-0000-0000-000000000000 b2c3d4e5-0000-0000-0000-000000000000]
      )
      expect(connection.nodes.map(&:repository)).to all(eq(presented_repository))
      expect(connection.nodes.map(&:organization)).to all(eq(organization))
    end
  end

  context 'when the list read reports the repository missing' do
    let(:page) { nil }

    it 'resolves the connection null rather than erroring' do
      expect(resolve_images).to be_nil
    end
  end

  context 'when the repository holds packages rather than images' do
    where(:format) { %w[maven npm] }

    with_them do
      it 'resolves the connection null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_images).to be_nil
        expect(client).not_to have_received(:images)
      end
    end
  end

  context 'when the repository is virtual' do
    let(:repository) do
      ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format, 'kind' => 'virtual')
    end

    where(:format) { %w[docker oci] }

    with_them do
      it 'resolves the connection null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_images).to be_nil
        expect(client).not_to have_received(:images)
      end
    end
  end

  context 'when the repository is hosted or remote' do
    let(:repository) do
      ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format, 'kind' => kind)
    end

    where(:kind) { %w[hosted remote] }

    with_them do
      it 'resolves the connection through Artifact Registry' do
        resolve_images

        expect(client).to have_received(:images)
      end
    end
  end
end
