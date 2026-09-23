# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::ArtifactRegistry::Versions::Delete, feature_category: :artifact_registry do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('ArtifactRegistryVersionDelete') }

  # No count field: Artifact Registry reports acceptance, not a result. Asserted on the declared
  # fields because a request spec cannot see a payload field no query selects.
  it { is_expected.to have_graphql_fields(:repository, :errors, :client_mutation_id) }

  it { is_expected.to have_graphql_arguments(:name, :id, :client_mutation_id) }
end
