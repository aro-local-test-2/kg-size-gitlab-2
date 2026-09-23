# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AiCatalogItemType'], feature_category: :ai_catalog_curation do
  it 'exposes all item types' do
    expect(described_class.values.keys).to match_array(%w[AGENT FLOW THIRD_PARTY_FLOW FOUNDATIONAL_AGENT])
  end
end
