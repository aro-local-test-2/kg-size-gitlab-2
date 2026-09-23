# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryNpmPackageDetails'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryNpmPackageDetails') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes every npm list-element field plus the dist-tags connection' do
    is_expected.to have_graphql_fields(
      :id, :name, :scope, :versions_count, :last_downloaded_at, :versions, :dist_tags
    )
  end

  # The list element type does NOT gain distTags: that is what keeps the packages connection's
  # fan-out bound unchanged.
  it 'is a distinct schema type from the npm list element, which has no dist_tags', :aggregate_failures do
    expect(described_class).not_to eq(GitlabSchema.types['ArtifactRegistryNpmPackage'])
    expect(described_class.interfaces).to be_empty
    expect(GitlabSchema.types['ArtifactRegistryNpmPackage'].fields).not_to have_key('distTags')
  end

  describe 'the dist-tags connection' do
    let(:field) { described_class.fields['distTags'] }

    it 'is the dist-tag connection, nullable, keyset-only, capped at 100, and budgeted',
      :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryNpmDistTagConnection')
      expect(field.type).to be_nullable
      expect(field.arguments.keys).to contain_exactly('first', 'last', 'before', 'after')
      expect(field.max_page_size).to eq(100)
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::NpmDistTagsResolver)
    end
  end
end
