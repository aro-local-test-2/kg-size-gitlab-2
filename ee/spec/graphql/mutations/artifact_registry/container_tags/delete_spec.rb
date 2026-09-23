# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::ArtifactRegistry::ContainerTags::Delete, feature_category: :artifact_registry do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('ArtifactRegistryContainerTagDelete') }

  it { is_expected.to have_graphql_fields(:repository, :errors, :client_mutation_id) }

  it { is_expected.to have_graphql_arguments(:name, :image_id, :tag_name, :client_mutation_id) }
end
