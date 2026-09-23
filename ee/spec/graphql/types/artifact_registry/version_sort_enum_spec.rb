# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryVersionSort'], feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryVersionSort') }

  it 'maps an ascending and a descending name to each column the endpoint backs, and offers no others' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'CREATED_AT_ASC' => { sort: 'created_at', order: 'asc' },
      'CREATED_AT_DESC' => { sort: 'created_at', order: 'desc' },
      'VERSION_ASC' => { sort: 'version', order: 'asc' },
      'VERSION_DESC' => { sort: 'version', order: 'desc' }
    )
  end
end
