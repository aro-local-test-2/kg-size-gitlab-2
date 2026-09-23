# frozen_string_literal: true

module Mcp
  module Tools
    module Security
      class ListVulnerabilitiesTool < Mcp::Tools::Base::GraphqlTool
        include Mcp::Tools::Concerns::CursorPagination

        register_version VERSIONS[:v0_1_0], {
          operation_name: 'project',
          graphql_operation: load_graphql('security/list_vulnerabilities.query.graphql')
        }

        protected

        def build_variables_v0_1_0
          project_full_path = params[:project_full_path]

          {
            fullPath: project_full_path,
            severity: params[:severity].presence,
            reportType: params[:report_type].presence,
            state: params[:state].presence,
            first: paginated_first,
            after: params[:after]
          }.compact
        end

        private

        def process_result(result)
          return resource_not_found_error if resource_not_found?(result)

          processed_result = super
          return processed_result if processed_result[:isError]

          vulnerabilities = processed_result[:structuredContent]['vulnerabilities']
          return ::Mcp::Tools::Base::Response.error('Operation returned no data') unless vulnerabilities

          formatted_content = [{ type: 'text', text: Gitlab::Json.dump(vulnerabilities) }]
          ::Mcp::Tools::Base::Response.success(formatted_content, vulnerabilities)
        end

        def resource_not_found_error
          ::Mcp::Tools::Base::Response.error(
            'Project not found: it does not exist or you do not have access to it.'
          )
        end
      end
    end
  end
end
