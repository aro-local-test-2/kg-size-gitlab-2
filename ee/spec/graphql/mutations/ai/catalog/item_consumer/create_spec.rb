# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::Catalog::ItemConsumer::Create, feature_category: :ai_catalog_curation do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('AiCatalogItemConsumerCreate') }

  it { expect(described_class).to require_graphql_authorizations(:create_ai_catalog_item_consumer) }

  it { is_expected.to have_graphql_fields(:item_consumer, :errors, :client_mutation_id) }

  it 'has expected arguments' do
    is_expected.to have_graphql_arguments(
      :item_id,
      :target,
      :trigger_types,
      :trigger_filter,
      :trigger_conditions,
      :parent_item_consumer_id,
      :consumer_kind,
      :pinned_version,
      :client_mutation_id
    )
  end
end
