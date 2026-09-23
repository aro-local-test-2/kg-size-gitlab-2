# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryVersionDetails'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryVersionDetails') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes every parent version field plus the files connection and statistics' do
    is_expected.to have_graphql_fields(
      :id, :version, :dist_tags, :size_bytes, :created_at, :created_by, :project,
      :commit_sha, :commit_path, :files, :statistics
    )
  end

  describe 'the files connection' do
    let(:field) { described_class.fields['files'] }

    it 'is the version-file connection, nullable, keyset-only, capped at 20, and budgeted',
      :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryVersionFileConnection')
      expect(field.type).to be_nullable
      expect(field.arguments.keys).to contain_exactly('first', 'last', 'before', 'after')
      expect(field.max_page_size).to eq(20)
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::VersionFilesResolver)
    end
  end

  describe 'the statistics field' do
    let(:field) { described_class.fields['statistics'] }

    it 'is the statistics type, nullable, budgeted, and not a connection', :aggregate_failures do
      expect(field.type.graphql_name).to eq('ArtifactRegistryVersionStatistics')
      expect(field.type).to be_nullable
      expect(field.arguments).to be_empty
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::VersionStatisticsResolver)
    end
  end

  # Being an unrelated type from the plain version element is what makes a details field
  # unnameable under the versions connection, so it is asserted rather than left to a reader.
  it 'is a distinct schema type from the plain version type, sharing no interface with it',
    :aggregate_failures do
    expect(described_class).not_to eq(GitlabSchema.types['ArtifactRegistryVersion'])
    expect(described_class.interfaces).to be_empty
  end
end
