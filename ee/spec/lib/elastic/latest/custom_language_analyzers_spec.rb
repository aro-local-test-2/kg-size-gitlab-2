# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Elastic::Latest::CustomLanguageAnalyzers do
  describe '.custom_analyzers_mappings' do
    before do
      allow(::Gitlab::CurrentSettings).to receive_messages(
        elasticsearch_analyzers_smartcn_enabled: true,
        elasticsearch_analyzers_kuromoji_enabled: true
      )
    end

    it 'returns correct structure' do
      expect(described_class.custom_analyzers_mappings).to eq(
        {
          properties: {
            title: {
              fields: described_class.custom_analyzers_fields(type: :text)
            },
            description: {
              fields: described_class.custom_analyzers_fields(type: :text)
            }
          }
        }
      )
    end
  end

  describe '.custom_analyzers_fields' do
    using RSpec::Parameterized::TableSyntax

    where(:smartcn_enabled, :kuromoji_enabled, :expected_result) do
      false | false | {}
      true  | false | { smartcn: { analyzer: 'smartcn', type: :text } }
      false | true  | { kuromoji: { analyzer: 'kuromoji', type: :text } }
      true  | true  | { smartcn: { analyzer: 'smartcn', type: :text }, kuromoji: { analyzer: 'kuromoji', type: :text } }
    end

    with_them do
      before do
        allow(::Gitlab::CurrentSettings).to receive_messages(
          elasticsearch_analyzers_smartcn_enabled: smartcn_enabled,
          elasticsearch_analyzers_kuromoji_enabled: kuromoji_enabled
        )
      end

      it 'returns correct config' do
        expect(described_class.custom_analyzers_fields(type: :text)).to eq(expected_result)
      end
    end
  end

  describe '.add_custom_analyzers_fields' do
    using RSpec::Parameterized::TableSyntax

    let!(:original_fields) { %w[title^2 confidential].freeze }

    where(:smartcn_enabled, :kuromoji_enabled, :smartcn_search, :kuromoji_search, :expected_additional_fields) do
      false | false | false | false  | []
      false | false | true  | true   | []
      true  | true  | false | false  | []
      true  | true  | true  | false  | %w[title.smartcn]
      true  | true  | false | true   | %w[title.kuromoji]
      true  | true  | true  | true   | %w[title.smartcn title.kuromoji]
    end

    with_them do
      before do
        allow(::Gitlab::CurrentSettings).to receive_messages(
          elasticsearch_analyzers_smartcn_enabled: smartcn_enabled,
          elasticsearch_analyzers_kuromoji_enabled: kuromoji_enabled,
          elasticsearch_analyzers_smartcn_search: smartcn_search,
          elasticsearch_analyzers_kuromoji_search: kuromoji_search
        )
      end

      it 'returns correct fields' do
        expect(described_class.add_custom_analyzers_fields(original_fields.dup)).to eq(original_fields + expected_additional_fields)
      end
    end
  end
end
