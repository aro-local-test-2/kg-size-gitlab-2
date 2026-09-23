# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryNpmDistTag'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryNpmDistTag') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the identifier, name, and the version it points at' do
    is_expected.to have_graphql_fields(:id, :name, :version_id, :version)
  end

  describe 'field types' do
    it 'renders name, versionId, and version as non-null', :aggregate_failures do
      expect(described_class.fields['name'].type).to be_non_null
      expect(described_class.fields['versionId'].type).to be_non_null
      expect(described_class.fields['version'].type).to be_non_null
    end

    it 'renders the tagged version id as an AR-native ID' do
      expect(described_class.fields['versionId'].type.unwrap.graphql_name).to eq('ID')
    end
  end
end
