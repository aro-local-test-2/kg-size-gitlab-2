# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::ArtifactRegistry::UpstreamRepositories::Dissociate,
  feature_category: :artifact_registry do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('ArtifactRegistryUpstreamRepositoryDissociate') }

  it { is_expected.to have_graphql_fields(:errors, :client_mutation_id) }

  it { is_expected.to have_graphql_arguments(:name, :format, :association_id, :client_mutation_id) }

  it 'requires every argument except the client mutation id', :aggregate_failures do
    expect(mutation.arguments['name'].type.non_null?).to be(true)
    expect(mutation.arguments['format'].type.non_null?).to be(true)
    expect(mutation.arguments['associationId'].type.non_null?).to be(true)
    expect(mutation.arguments['clientMutationId'].type.non_null?).to be(false)
  end
end
