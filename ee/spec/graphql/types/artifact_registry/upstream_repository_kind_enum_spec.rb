# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryUpstreamRepositoryKind'], feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryUpstreamRepositoryKind') }

  it 'narrows the repository kinds to the two an upstream can be, and offers no others' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'HOSTED' => 'hosted',
      'REMOTE' => 'remote'
    )
  end
end
