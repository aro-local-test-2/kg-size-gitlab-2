# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::RepositoriesResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:page) { ArtifactRegistry::Page.new(nodes: []) }
  let(:client) { instance_double(ArtifactRegistry::Client, repositories: page) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }
  let(:max_page_size) { GitlabSchema.default_max_page_size }
  let(:default_sort) { { sort: 'last_updated_at', order: 'desc' } }
  let(:args) { {} }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_repositories) do
    resolve(
      described_class,
      obj: organization,
      args: args,
      ctx: { current_user: current_user },
      field_opts: { connection_extension: ::Gitlab::Graphql::Extensions::ExternallyPaginatedArrayExtension }
    )
  end

  it "reads the organization's resolved slug at the schema's default page size" do
    resolve_repositories

    expect(client).to have_received(:repositories)
      .with(slug: slug, limit: max_page_size, **default_sort, include_permissions: false)
  end

  context 'with a requested page size below the maximum' do
    let(:args) { { first: 10 } }

    it 'forwards the requested size as the outbound limit' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, limit: 10, **default_sort, include_permissions: false)
    end
  end

  context 'with a requested page size above the maximum' do
    let(:args) { { first: GitlabSchema.default_max_page_size + 1 } }

    it 'caps the outbound limit at the maximum' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, limit: max_page_size, **default_sort, include_permissions: false)
    end
  end

  describe 'the resolved nodes' do
    let(:repository) { ArtifactRegistry::Repository.new('name' => 'maven-releases', 'format' => 'maven') }
    let(:page) { ArtifactRegistry::Page.new(nodes: [repository]) }

    # The list resolves the bare value object: only the detail type mounts a child connection,
    # so nothing here needs the organization a presenter would carry.
    #
    # `skip_type_authorization` mirrors the field's own mount, and goes in the context rather
    # than `field_opts`: the extension sets the same key through `scoped_set!` during
    # resolution, and `.nodes` is read after that scope closes.
    it 'resolves each repository unwrapped', :aggregate_failures do
      nodes = resolve(
        described_class,
        obj: organization,
        args: args,
        ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] },
        field_opts: { connection_extension: ::Gitlab::Graphql::Extensions::ExternallyPaginatedArrayExtension }
      ).nodes

      expect(nodes).to all(be_an_instance_of(ArtifactRegistry::Repository))
      expect(nodes.map(&:name)).to eq(['maven-releases'])
    end
  end

  describe 'the permissions blocks' do
    it 'asks for no verdicts when the selection includes neither block' do
      resolve_repositories

      expect(client).to have_received(:repositories).with(hash_including(include_permissions: false))
    end

    it 'asks for verdicts and carries the page permissions when a block is selected', :aggregate_failures do
      permissions = ArtifactRegistry::Permissions::Verdicts.absent(scope: :namespace, read: :repositories, slug: slug)
      allow(client).to receive(:repositories)
        .and_return(ArtifactRegistry::Page.new(nodes: [], permissions: permissions))

      connection = resolve(
        described_class,
        obj: organization,
        args: args,
        ctx: { current_user: current_user },
        lookahead: positive_lookahead,
        field_opts: { connection_extension: ::Gitlab::Graphql::Extensions::ExternallyPaginatedArrayExtension }
      )

      expect(client).to have_received(:repositories).with(hash_including(include_permissions: true))
      expect(connection.items).to be_a(Gitlab::Graphql::ArtifactRegistry::RepositoriesPage)
      expect(connection.items.permissions).to be(permissions)
    end
  end

  it 'sends no filter when neither is requested' do
    resolve_repositories

    expect(client).to have_received(:repositories).with(hash_not_including(:format, :kind))
  end

  context 'with a format filter' do
    ::Types::ArtifactRegistry::RepositoryFormatEnum.values.each_value do |enum_value|
      context "for #{enum_value.graphql_name}" do
        let(:args) { { format: enum_value.value } }

        it 'forwards the wire value the contract expects' do
          resolve_repositories

          expect(client).to have_received(:repositories)
            .with(slug: slug, format: enum_value.value, limit: max_page_size, **default_sort,
              include_permissions: false)
        end
      end
    end
  end

  context 'with a kind filter' do
    ::Types::ArtifactRegistry::RepositoryKindEnum.values.each_value do |enum_value|
      context "for #{enum_value.graphql_name}" do
        let(:args) { { kind: enum_value.value } }

        it 'forwards the wire value the contract expects' do
          resolve_repositories

          expect(client).to have_received(:repositories)
            .with(slug: slug, kind: enum_value.value, limit: max_page_size, **default_sort, include_permissions: false)
        end
      end
    end
  end

  context 'with both filters and a page size' do
    let(:args) { { format: 'maven', kind: 'hosted', first: 10 } }

    it 'forwards both alongside the outbound limit' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, format: 'maven', kind: 'hosted', limit: 10, **default_sort, include_permissions: false)
    end
  end

  context 'with a formats filter' do
    let(:args) { { formats: %w[docker oci] } }

    it 'forwards the list under the single-valued parameter name the contract expects' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, format: %w[docker oci], limit: max_page_size, **default_sort, include_permissions: false)
    end
  end

  context 'with a kinds filter' do
    let(:args) { { kinds: %w[hosted remote] } }

    it 'forwards the list under the single-valued parameter name the contract expects' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, kind: %w[hosted remote], limit: max_page_size, **default_sort, include_permissions: false)
    end
  end

  context 'with both list filters and a page size' do
    let(:args) { { formats: %w[maven], kinds: %w[hosted remote], first: 10 } }

    it 'forwards both alongside the outbound limit' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, format: %w[maven], kind: %w[hosted remote], limit: 10, **default_sort,
          include_permissions: false)
    end
  end

  context 'with empty list filters' do
    let(:args) { { formats: [], kinds: [] } }

    it 'sends no filter, so an empty list reaches Artifact Registry as no value rather than a blank one' do
      resolve_repositories

      expect(client).to have_received(:repositories).with(hash_not_including(:format, :kind))
    end
  end

  describe 'the mutually exclusive filters' do
    context 'with both a format and a formats list' do
      let(:args) { { format: 'maven', formats: %w[maven] } }

      it 'creates a top-level error and reaches no client read', :aggregate_failures do
        expect_graphql_error_to_be_created(GraphQL::Schema::Validator::ValidationFailedError,
          'Only one of [format, formats] arguments is allowed at the same time.') do
          resolve_repositories
        end

        expect(client).not_to have_received(:repositories)
      end
    end

    context 'with both a kind and a kinds list' do
      let(:args) { { kind: 'hosted', kinds: %w[hosted] } }

      it 'creates a top-level error and reaches no client read', :aggregate_failures do
        expect_graphql_error_to_be_created(GraphQL::Schema::Validator::ValidationFailedError,
          'Only one of [kind, kinds] arguments is allowed at the same time.') do
          resolve_repositories
        end

        expect(client).not_to have_received(:repositories)
      end
    end
  end

  context 'when paging forward' do
    let(:args) { { first: 10, after: 'NEXT_CURSOR' } }

    it 'forwards the forward cursor' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, limit: 10, cursor: 'NEXT_CURSOR', **default_sort, include_permissions: false)
    end
  end

  context 'when paging backward' do
    let(:args) { { last: 5, before: 'PREV_CURSOR' } }

    it 'forwards the backward cursor' do
      resolve_repositories

      expect(client).to have_received(:repositories)
        .with(slug: slug, limit: 5, cursor: 'PREV_CURSOR', **default_sort, include_permissions: false)
    end
  end

  describe 'the sort argument' do
    using RSpec::Parameterized::TableSyntax

    where(:sort_name, :expected_sort, :expected_order) do
      'NAME_ASC'             | 'name'            | 'asc'
      'NAME_DESC'            | 'name'            | 'desc'
      'LAST_UPDATED_AT_ASC'  | 'last_updated_at' | 'asc'
      'LAST_UPDATED_AT_DESC' | 'last_updated_at' | 'desc'
      'DOWNLOADS_COUNT_ASC'  | 'downloads_count' | 'asc'
      'DOWNLOADS_COUNT_DESC' | 'downloads_count' | 'desc'
      'SIZE_BYTES_ASC'       | 'size_bytes'      | 'asc'
      'SIZE_BYTES_DESC'      | 'size_bytes'      | 'desc'
    end

    with_them do
      let(:args) { { sort: sort_name } }

      it 'reaches the client as the column and direction the contract expects' do
        resolve_repositories

        expect(client).to have_received(:repositories)
          .with(slug: slug, limit: max_page_size, sort: expected_sort, order: expected_order,
            include_permissions: false)
      end
    end

    context 'when the argument is explicitly null' do
      let(:args) { { sort: nil } }

      it 'reaches the client as the default column and direction' do
        resolve_repositories

        expect(client).to have_received(:repositories)
          .with(slug: slug, limit: max_page_size, **default_sort, include_permissions: false)
      end
    end
  end
end
