# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::SemanticSearch::SemanticSearchService, feature_category: :mcp_server do
  let(:mock_code_tool) { instance_double(Mcp::Tools::Base::ApiTool, name: 'semantic_code_search') }
  let(:tools) { [mock_code_tool] }
  let(:service) { described_class.new(tools: tools) }

  describe '.tool_name' do
    it 'returns the correct tool name' do
      expect(described_class.tool_name).to eq('semantic_search')
    end
  end

  describe '.tool_aliases' do
    it 'returns the backward-compatible alias' do
      expect(described_class.tool_aliases).to eq(['semantic_code_search'])
    end
  end

  describe '#description' do
    it 'includes key usage guidance' do
      expect(service.description).to include(
        'Semantic (meaning-based) search over different types of content.'
      )
    end
  end

  describe '#input_schema' do
    it 'matches the expected contract' do
      knn_default = ::Ai::ActiveContext::Queries::Code::KNN_COUNT
      limit_default = ::Ai::ActiveContext::Queries::Code::SEARCH_RESULTS_LIMIT

      expect(service.input_schema).to eq(
        {
          type: 'object',
          additionalProperties: false,
          required: %w[scope q project_id],
          properties: {
            scope: {
              type: 'string',
              enum: ['code'],
              description: "Specify the type of content to search for. Supported values:  " \
                "- 'code' - search code files."
            },
            q: {
              type: 'string',
              description: 'Natural language search query'
            },
            project_id: {
              type: 'string',
              description: 'The ID or full path of the project'
            },
            directory_path: {
              type: 'string',
              description: 'Restrict search to files under this directory path. ' \
                'Must be a relative path - no leading slash, no .. segments. Applies to scope "code" only.'
            },
            knn: {
              type: 'integer',
              minimum: 1,
              maximum: 100,
              description: "Number of nearest neighbours to retrieve internally " \
                "(default: #{knn_default}). " \
                'Higher values improve recall at the cost of latency. Applies to scope "code" only.'
            },
            limit: {
              type: 'integer',
              minimum: 1,
              maximum: 100,
              description: "Maximum number of results to return " \
                "(default: #{limit_default}). " \
                'Applies to scope "code" only.'
            }
          }
        }
      )
    end
  end

  describe '#execute' do
    let(:request) { nil }
    let(:mock_response) { { content: [{ type: 'text', text: 'results' }], isError: false } }

    context 'with scope: code' do
      let(:arguments) { { scope: 'code', q: 'authentication middleware', project_id: 'my-group/my-project' } }
      let(:params) { { arguments: arguments } }
      let(:transformed_params) do
        { arguments: { q: 'authentication middleware', id: 'my-group/my-project' } }
      end

      it 'routes to the semantic_code_search API tool' do
        expect(mock_code_tool).to receive(:execute)
          .with(request: request, params: transformed_params)
          .and_return(mock_response)

        result = service.execute(request: request, params: params)

        expect(result).to eq(mock_response)
      end

      context 'with optional params' do
        let(:arguments) do
          { scope: 'code', q: 'rate limiting', project_id: '123', directory_path: 'app/services/', knn: 32, limit: 10 }
        end

        let(:transformed_params) do
          { arguments: { q: 'rate limiting', directory_path: 'app/services/', knn: 32, limit: 10, id: '123' } }
        end

        it 'passes optional params through to the underlying tool' do
          expect(mock_code_tool).to receive(:execute)
            .with(request: request, params: transformed_params)
            .and_return(mock_response)

          service.execute(request: request, params: params)
        end
      end
    end

    context 'with an unsupported scope' do
      let(:arguments) { { scope: 'issues', q: 'test', project_id: '123' } }
      let(:params) { { arguments: arguments } }

      it 'returns a validation error' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include('Validation error')
        expect(result[:content].first[:text]).to include('scope')
      end
    end

    context 'when required params are missing' do
      let(:arguments) { { scope: 'code' } }
      let(:params) { { arguments: arguments } }

      it 'returns a validation error for missing q and project_id' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include('Validation error')
      end
    end

    context 'when the underlying tool is not found' do
      let(:service_with_no_tools) { described_class.new(tools: []) }
      let(:arguments) { { scope: 'code', q: 'test', project_id: '123' } }
      let(:params) { { arguments: arguments } }

      it 'returns an error response' do
        result = service_with_no_tools.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include("semantic_search is not available on this GitLab instance")
      end
    end
  end
end
