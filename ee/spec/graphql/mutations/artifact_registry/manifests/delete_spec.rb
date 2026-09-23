# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::ArtifactRegistry::Manifests::Delete, feature_category: :artifact_registry do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('ArtifactRegistryManifestDelete') }

  it { is_expected.to have_graphql_fields(:repository, :errors, :client_mutation_id) }

  it { is_expected.to have_graphql_arguments(:name, :image_id, :digest, :client_mutation_id) }
end
