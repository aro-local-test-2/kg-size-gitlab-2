# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::VersionsResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  # Per the GraphQL testing standard, this unit spec verifies only the static declarations
  # (the returned type, the call-count budget, and the sort argument). The resolver's behavior --
  # endpoint reads, sort splitting, limit capping, cursor forwarding, ordering, and the
  # null-on-missing page -- is exercised end to end in
  # ee/spec/requests/api/graphql/organizations/artifact_registry_versions_spec.rb.

  it 'returns the version connection type, nullable so a failed read hides it', :aggregate_failures do
    expect(described_class.type.unwrap.graphql_name).to eq('ArtifactRegistryVersionConnection')
    expect(described_class.type.non_null?).to be(false)
  end

  it 'budgets the field at 20 resolutions per operation, one per package in a page' do
    expect(described_class.extensions).to include({ ::Gitlab::Graphql::Limit::FieldCallCount => { limit: 20 } })
  end

  it 'takes an optional sort argument defaulting to publication date descending', :aggregate_failures do
    argument = described_class.arguments['sort']

    expect(argument.type).to eq(::Types::ArtifactRegistry::VersionSortEnum)
    expect(argument.default_value).to eq(described_class::DEFAULT_SORT)
    # An explicit `sort: null` becomes the default rather than reaching the resolver as nil.
    expect(argument.replace_null_with_default?).to be(true)
  end
end
