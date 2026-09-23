# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::Catalog::ItemConsumer::Delete, feature_category: :ai_catalog_curation do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('AiCatalogItemConsumerDelete') }

  it { expect(described_class).to require_graphql_authorizations(:admin_ai_catalog_item_consumer) }

  it { is_expected.to have_graphql_fields(:success, :errors, :client_mutation_id) }

  it { is_expected.to have_graphql_arguments(:id, :client_mutation_id) }
end
