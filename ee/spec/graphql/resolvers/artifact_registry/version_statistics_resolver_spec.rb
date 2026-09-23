# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::VersionStatisticsResolver, feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:format) { 'maven' }
  let(:kind) { 'hosted' }
  let(:repository_name) { 'maven-releases' }
  let(:version_id) { 'v1000000-0000-0000-0000-000000000000' }
  let(:repository) { ArtifactRegistry::Repository.new('name' => repository_name, 'format' => format, 'kind' => kind) }
  let(:version) { ArtifactRegistry::Version.new('id' => version_id) }
  let(:presented_version) do
    ArtifactRegistry::VersionPresenter.new(version, repository: repository, organization: organization)
  end

  let(:statistics) { ArtifactRegistry::VersionStatistics.new('files_count' => 12) }
  let(:client) { instance_double(ArtifactRegistry::Client, version_statistics: statistics) }
  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_statistics) do
    resolve(
      described_class,
      obj: presented_version,
      ctx: { current_user: current_user, skip_type_authorization: [:read_artifact_registry] }
    )
  end

  it 'limits the field to one resolution per request, ahead of any client call' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  context 'when the repository holds packages' do
    where(:format) { %w[maven npm] }

    with_them do
      it 'reads the statistics through the organization the presenter carries, by version ID' do
        resolve_statistics

        expect(client).to have_received(:version_statistics)
          .with(slug: slug, repository_name: repository_name, format: format, version_id: version_id)
      end

      it 'returns the statistics value object for a hosted repository' do
        expect(resolve_statistics).to be(statistics)
      end
    end
  end

  context 'when the repository is not hosted (statistics are hosted-only)' do
    where(:kind) { %w[virtual remote] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_statistics).to be_nil
        expect(client).not_to have_received(:version_statistics)
      end
    end
  end

  context 'when the repository holds images rather than packages' do
    where(:format) { %w[docker oci] }

    with_them do
      it 'resolves null without reaching Artifact Registry', :aggregate_failures do
        expect(resolve_statistics).to be_nil
        expect(client).not_to have_received(:version_statistics)
      end
    end
  end

  context 'when Artifact Registry does not serve the statistics route' do
    let(:client) { instance_double(ArtifactRegistry::Client, version_statistics: nil) }

    it 'resolves null rather than erroring' do
      expect(resolve_statistics).to be_nil
    end
  end

  context 'when the artifact_registry_ui feature flag is disabled' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'resolves null on the field itself, without calling the client', :aggregate_failures do
      expect(resolve_statistics).to be_nil
      expect(client).not_to have_received(:version_statistics)
    end
  end
end
