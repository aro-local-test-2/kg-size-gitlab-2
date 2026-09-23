# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::GlobalSearchSlis, feature_category: :global_search do
  using RSpec::Parameterized::TableSyntax

  describe '#initialize_slis!' do
    let(:aggregations_label) { a_hash_including(endpoint_id: 'SearchController#aggregations') }
    let(:semantic_label) do
      a_hash_including(
        search_type: 'semantic',
        search_level: 'project',
        search_scope: 'blobs',
        endpoint_id: 'GET /api/:version/projects/:id/(-/)search/semantic'
      )
    end

    where(:search_type, :search_scope, :search_level, :valid) do
      'advanced' | 'wiki_blobs' | 'global'  | true
      'advanced' | 'wiki_blobs' | 'project' | true
      'advanced' | 'blobs'      | 'global'  | true
      'zoekt'    | 'blobs'      | 'global'  | true
      'zoekt'    | 'blobs'      | 'group'   | true
      'zoekt'    | 'blobs'      | 'project' | true
      'advanced' | 'work_items' | 'global'  | true
      'basic'    | 'work_items' | 'global'  | true
      'basic'    | 'work_items' | 'group'   | true
      'zoekt'    | 'work_items' | 'global'  | false
      'zoekt'    | 'wiki_blobs' | 'global'  | false
    end

    with_them do
      it 'initializes valid label combinations and excludes impossible ones' do
        if valid
          expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(
            :global_search, array_including(a_hash_including(
              search_type: search_type, search_scope: search_scope, search_level: search_level
            ))
          )
        else
          expect(Gitlab::Metrics::Sli::Apdex).not_to receive(:initialize_sli).with(
            :global_search, array_including(a_hash_including(
              search_type: search_type, search_scope: search_scope, search_level: search_level
            ))
          )
        end

        described_class.initialize_slis!
      end
    end

    context 'when running in a web environment' do
      before do
        allow(Gitlab::Metrics::Environment).to receive_messages(web?: true, api?: false)
      end

      it 'includes SearchController#aggregations in Apdex SLI labels' do
        expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(
          :global_search, array_including(aggregations_label)
        )

        described_class.initialize_slis!
      end

      it 'includes SearchController#aggregations in ErrorRate SLI labels' do
        expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(
          :global_search, array_including(aggregations_label)
        )

        described_class.initialize_slis!
      end
    end

    context 'when running in an API environment' do
      before do
        allow(Gitlab::Metrics::Environment).to receive_messages(web?: false, api?: true)
      end

      it 'does not include SearchController#aggregations in SLI labels' do
        expect(Gitlab::Metrics::Sli::Apdex).not_to receive(:initialize_sli).with(
          :global_search, array_including(aggregations_label)
        )

        described_class.initialize_slis!
      end

      it 'includes the semantic code search endpoint label' do
        expect(Gitlab::Metrics::Sli::Apdex).to receive(:initialize_sli).with(
          :global_search, array_including(semantic_label)
        )

        described_class.initialize_slis!
      end

      it 'includes the semantic code search endpoint in ErrorRate SLI labels' do
        expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(
          :global_search, array_including(semantic_label)
        )

        described_class.initialize_slis!
      end
    end

    context 'when running in a non-API environment' do
      before do
        allow(Gitlab::Metrics::Environment).to receive_messages(web?: true, api?: false)
      end

      it 'does not include the semantic code search endpoint label' do
        expect(Gitlab::Metrics::Sli::Apdex).not_to receive(:initialize_sli).with(
          :global_search, array_including(semantic_label)
        )

        described_class.initialize_slis!
      end
    end
  end

  describe 'SEMANTIC_ENDPOINT_ID' do
    # The constant pre-registers the series, but the label actually recorded at request
    # time comes from ApplicationContext's caller_id. Pin it to the route object so a
    # path rename fails here instead of silently splitting the metric in two.
    it 'matches the endpoint that records it' do
      route = ::EE::API::Search::SemanticCodeSearch.routes.first

      expect(::API::Base.endpoint_id_for_route(route))
        .to eq(::EE::Gitlab::Metrics::GlobalSearchSlis::SEMANTIC_ENDPOINT_ID)
    end
  end

  describe '#duration_target' do
    subject(:target) { described_class.send(:duration_target, search_type, 'blobs') }

    context 'for the semantic search type' do
      let(:search_type) { 'semantic' }

      it 'returns the dedicated semantic target rather than falling through' do
        expect(target).to eq(::EE::Gitlab::Metrics::GlobalSearchSlis::SEMANTIC_TARGET_S)
      end

      it 'matches the 5s the endpoint declares via urgency :low' do
        low = ::Gitlab::EndpointAttributes::Config::REQUEST_URGENCIES[:low]

        expect(target).to eq(low.duration)
      end
    end

    context 'for a non-semantic search type' do
      let(:search_type) { 'zoekt' }

      it 'delegates to the CE implementation' do
        # The CE targets are defined inside `class << self`, so they live on the
        # singleton class rather than on the module.
        expect(target).to eq(described_class.singleton_class::ZOEKT_TARGET_S)
      end
    end
  end

  describe '#record_apdex' do
    before do
      allow(Gitlab::Metrics::Sli::Apdex).to receive(:[]).with(:global_search).and_return(apdex)
      allow(Gitlab::AppJsonLogger).to receive(:info)
    end

    let(:apdex) { instance_double(Gitlab::Metrics::Sli::Apdex, increment: nil) }

    def record(elapsed)
      described_class.record_apdex(
        elapsed: elapsed,
        search_type: 'semantic',
        search_level: 'project',
        search_scope: 'blobs'
      )
    end

    it 'counts a semantic search under the target as a success' do
      expect(apdex).to receive(:increment).with(hash_including(success: true))

      record(::EE::Gitlab::Metrics::GlobalSearchSlis::SEMANTIC_TARGET_S - 0.1)
    end

    it 'counts a semantic search over the target as a failure' do
      expect(apdex).to receive(:increment).with(hash_including(success: false))

      record(::EE::Gitlab::Metrics::GlobalSearchSlis::SEMANTIC_TARGET_S + 0.1)
    end
  end
end
