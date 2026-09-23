# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Catalog::ItemInterface, feature_category: :ai_catalog_curation do
  include GraphqlHelpers

  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiCatalogItem')
  end

  it 'has the expected fields' do
    expected_fields = %w[
      created_at
      configuration_for_group
      configuration_for_project
      description
      description_html
      foundational
      id
      item_type
      name
      latest_version
      effective_version
      project
      public
      visibility
      soft_deleted
      soft_deleted_at
      updated_at
      user_permissions
      versions
      foundational_flow_reference
      verification_level
      last_30_day_usage_count
      is_enabled_in_managed_by_project
      star_count
      starred
      web_path
    ]

    expect(described_class).to have_graphql_fields(*expected_fields)
  end

  describe ".resolve_type" do
    let_it_be(:user) { create(:user) }
    let_it_be(:item) { create(:ai_catalog_item, item_type: 'agent') }

    let(:context) { {} }

    subject(:resolve_type) { described_class.resolve_type(item, context) }

    it { is_expected.to eq(Types::Ai::Catalog::AgentType) }

    context 'when item_type is unknown' do
      before do
        allow(item).to receive(:item_type).and_return('unknown_type')
      end

      it 'raises an error' do
        expect { resolve_type }.to raise_exception(StandardError, 'Unknown catalog item type: unknown_type')
      end
    end
  end

  describe '#web_path' do
    subject(:web_path) { Gitlab::Graphql::Lazy.force(resolve_field(:web_path, item, object_type: object_type)) }

    before do
      allow(object_type).to receive(:authorized?).and_return(true)
    end

    context 'for a flow' do
      let(:object_type) { ::Types::Ai::Catalog::FlowType }
      let(:item) { build_stubbed(:ai_catalog_flow) }

      it { is_expected.to eq("/explore/ai-catalog/flows/#{item.id}") }
    end

    context 'for an agent' do
      let(:object_type) { ::Types::Ai::Catalog::AgentType }
      let(:item) { build_stubbed(:ai_catalog_agent) }

      it { is_expected.to eq("/explore/ai-catalog/agents/#{item.id}") }
    end

    context 'for a third-party flow' do
      let(:object_type) { ::Types::Ai::Catalog::ThirdPartyFlowType }
      let(:item) { build_stubbed(:ai_catalog_third_party_flow) }

      it { is_expected.to eq("/explore/ai-catalog/agents/#{item.id}") }
    end
  end

  describe 'is_enabled_in_managed_by_project field' do
    subject(:field) { described_class.fields['isEnabledInManagedByProject'] }

    it 'limits field call count' do
      extension = field.extensions.find { |e| e.is_a?(::Gitlab::Graphql::Limit::FieldCallCount) }

      expect(extension).to be_present
      expect(extension.options).to eq(limit: 1)
    end
  end
end
