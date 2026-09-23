# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::VersionFilesResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  it 'returns the version-file connection type, nullable so a failed read hides it', :aggregate_failures do
    expect(described_class.type.unwrap.graphql_name).to eq('ArtifactRegistryVersionFileConnection')
    expect(described_class.type.non_null?).to be(false)
  end

  it 'limits the field to one resolution per operation, its own budget separate from version' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 1 } })
  end

  it 'declares no sort or order argument, since the endpoint sorts by file name alone' do
    expect(described_class.arguments.keys).not_to include('sort', 'order')
  end
end
