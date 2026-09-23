# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryNpmVersionFile'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryNpmVersionFile') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the identifier plus the npm file fields, and no Maven-only checksum' do
    is_expected.to have_graphql_fields(:id, :file_name, :size_bytes, :sha256, :created_at)
  end

  describe 'field nullability' do
    it 'renders sha256 non-null and createdAt nullable, for a remote cached row', :aggregate_failures do
      expect(described_class.fields['sha256'].type).to be_non_null
      expect(described_class.fields['createdAt'].type).to be_nullable
    end
  end
end
