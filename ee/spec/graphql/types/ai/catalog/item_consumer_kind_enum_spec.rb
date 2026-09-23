# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AiCatalogItemConsumerKind'], feature_category: :ai_catalog_curation do
  it 'exposes all item consumer kinds' do
    expect(described_class.values.keys).to match_array(%w[DIRECT INHERITANCE])
  end
end
