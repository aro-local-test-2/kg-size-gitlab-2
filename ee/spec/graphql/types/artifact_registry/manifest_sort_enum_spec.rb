# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryManifestSort'], feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryManifestSort') }

  it 'offers publication date alone, matching the only column the manifests endpoint sorts by' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'CREATED_AT_ASC' => { sort: 'created_at', order: 'asc' },
      'CREATED_AT_DESC' => { sort: 'created_at', order: 'desc' }
    )
  end
end
