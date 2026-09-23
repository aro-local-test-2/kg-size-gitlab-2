# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::ManifestsResolver, feature_category: :artifact_registry do
  # Per the GraphQL testing standard, this unit spec asserts only the static declarations
  # (return type and call-count budget); the resolver's behavior runs end to end in
  # ee/spec/requests/api/graphql/organizations/artifact_registry_manifests_spec.rb.

  it 'returns the manifest connection type, nullable so a failed read hides it', :aggregate_failures do
    expect(described_class.type.unwrap.graphql_name).to eq('ArtifactRegistryManifestConnection')
    expect(described_class.type.non_null?).to be(false)
  end

  it 'budgets the field at the parent images page size, so aliases cannot multiply the fan-out' do
    expect(described_class.extensions).to include(
      { ::Gitlab::Graphql::Limit::FieldCallCount => { limit: ::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE } }
    )
  end

  it 'declares the sort argument with a publication-date-descending default', :aggregate_failures do
    arg = described_class.arguments['sort']

    expect(arg.type).to eq(::Types::ArtifactRegistry::ManifestSortEnum)
    expect(arg.default_value).to eq(described_class::DEFAULT_SORT)
    # An explicit `sort: null` becomes the default rather than reaching the resolver as nil.
    expect(arg.replace_null_with_default?).to be(true)
  end

  it 'declares the referrer-inclusion argument defaulting to false' do
    arg = described_class.arguments['includeReferrers']

    expect(arg.type.to_type_signature).to eq('Boolean')
    expect(arg.default_value).to be(false)
  end
end
