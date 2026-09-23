# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::UpstreamRepositoriesResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:repository_format) { 'maven' }
  let(:repository_name) { 'maven-virtual' }
  let(:kind) { 'virtual' }
  let(:repository) do
    ArtifactRegistry::Repository.new('name' => repository_name, 'format' => repository_format, 'kind' => kind)
  end

  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: organization) }
  let(:associations) do
    [
      ArtifactRegistry::UpstreamRepositoryAssociation.new('id' => 'assoc-1', 'position' => 1),
      ArtifactRegistry::UpstreamRepositoryAssociation.new('id' => 'assoc-2', 'position' => 2)
    ]
  end

  let(:client) { instance_double(ArtifactRegistry::Client, upstream_repositories: associations) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_upstreams) do
    resolve(
      described_class,
      obj: presented_repository,
      args: {},
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] }
    )
  end

  it 'limits the field to one resolution per request, ahead of any client call' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  describe 'reading the upstream list under the repository format segment' do
    where(:repository_format, :repository_name) do
      'maven'  | 'maven-virtual'
      'npm'    | 'npm-virtual'
      'docker' | 'docker-virtual'
      'oci'    | 'oci-virtual'
    end

    with_them do
      it 'issues one upstream-list read with the slug, repository name, and format' do
        resolve_upstreams

        expect(client).to have_received(:upstream_repositories)
          .with(slug: slug, repository_name: repository_name, format: repository_format)
      end
    end
  end

  it 'returns the associations in the order Artifact Registry sent them' do
    expect(resolve_upstreams).to eq(associations)
  end

  context 'when the repository is hosted or remote' do
    where(:kind) { %w[hosted remote] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_upstreams).to be_nil
        expect(client).not_to have_received(:upstream_repositories)
      end
    end
  end

  context 'when the list read reports the repository missing' do
    let(:client) { instance_double(ArtifactRegistry::Client, upstream_repositories: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_upstreams).to be_nil
    end
  end
end
