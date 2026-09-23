# frozen_string_literal: true

module Mcp
  module Tools
    module SemanticSearch
      class SemanticSearchService < Base::AggregatedService
        extend ::Gitlab::Utils::Override

        register_version '0.1.0', {
          toolset: :core,
          annotations: {
            readOnlyHint: true
          }
        }

        override :tool_name
        def self.tool_name
          'semantic_search'
        end

        override :tool_aliases
        def self.tool_aliases
          ['semantic_code_search']
        end

        override :description
        def description
          <<~DESC.strip
            Semantic (meaning-based) search over different types of content.

            Searches indexed project content using embedding-based similarity rather than
            keyword matching. Use this when you do not know the exact symbol or file name,
            or to discover how a behavior is implemented across the codebase.

            Primary use cases:
            - When you do not know the exact symbol or file path
            - To see how a behavior or feature is implemented across the codebase
            - To discover related implementations (clients, jobs, workers)

            How to use:
            - Provide a concise, specific query with concrete keywords
            - Use directory_path to narrow scope when scope is "code"
            - Prefer precise intent over broad terms

            Results are grouped by file. Each file includes merged line ranges with content
            and a relevance score (0.0-1.0). The response includes an overall confidence
            level (high/medium/low/unknown) based on score distribution.

            Requires semantic search to be enabled and indexed for the project namespace.
          DESC
        end

        override :input_schema
        def input_schema
          scope_desc = "Specify the type of content to search for. " \
            "Supported values:  " \
            "- 'code' - search code files."

          Mcp::Tools::Base::SchemaDefaults.with_additional_properties(
            type: 'object',
            properties: {
              scope: {
                type: 'string',
                enum: ['code'],
                description: scope_desc
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
                  "(default: #{::Ai::ActiveContext::Queries::Code::KNN_COUNT}). " \
                  'Higher values improve recall at the cost of latency. Applies to scope "code" only.'
              },
              limit: {
                type: 'integer',
                minimum: 1,
                maximum: 100,
                description: "Maximum number of results to return " \
                  "(default: #{::Ai::ActiveContext::Queries::Code::SEARCH_RESULTS_LIMIT}). " \
                  'Applies to scope "code" only.'
              }
            },
            required: %w[scope q project_id]
          )
        end

        override :select_tool
        def select_tool(args)
          case args[:scope]
          when 'code'
            tools.find { |tool| tool.name.to_s == 'semantic_code_search' }
          end
        end

        override :transform_arguments
        def transform_arguments(args)
          args.except(:scope, :project_id).merge(id: args[:project_id])
        end
      end
    end
  end
end
