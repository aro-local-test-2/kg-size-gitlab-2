# frozen_string_literal: true

module QA
  module EE
    module Resource
      module Ai
        class DuoWorkflow < QA::Resource::Base
          FOUNDATIONAL_FLOWS = {
            'developer/v1' => {
              default_goal: 'Create a file hello.txt at the repository root containing: hello from dap'
            }
          }.freeze

          DEFAULT_WORKFLOW_DEFINITION = 'developer/v1'

          attr_accessor :project, :workflow_definition
          attr_writer :goal, :start_workflow
          attr_reader :id, :workload_id, :status, :api_response

          # Flows triggered from inside GitLab, such as Code Review from a reviewer assignment,
          # are created server side, so a spec discovers the workflow instead of fabricating it.
          # Returns nil while the project has no flow yet, so callers can poll.
          #
          # @param project [QA::Resource::Project] a project that runs a single flow
          # @param api_client [QA::Runtime::API::Client]
          # @return [DuoWorkflow, nil]
          def self.find_latest_in_project(project, api_client:)
            flow = new
            flow.api_client = api_client
            flow.project = project

            flow if flow.reload_latest!
          end

          def initialize
            @workflow_definition = DEFAULT_WORKFLOW_DEFINITION
            @start_workflow = true
          end

          def goal
            @goal || flow_config.fetch(:default_goal)
          end

          def api_support?
            true
          end

          def fabricate_via_api!
            @api_response = api_post_to(api_post_path, api_post_body)
            @api_fabrication_http_method = :post
            @id = api_response[:id]
            @workload_id = api_response.dig(:workload, :id)
            @status = api_response[:status]

            api_response[:gitlab_url] || QA::Runtime::Scenario.gitlab_address
          end

          # No per-workflow cleanup: duo_workflows_workflows.project_id has a DB-level
          # ON DELETE CASCADE, so the workflow (and its pipeline/checkpoints) is removed when
          # its project is deleted in the spec teardown.
          def remove_via_api!; end

          def api_post_path
            '/ai/duo_workflows/workflows'
          end

          def api_post_body
            {
              project_id: project.id.to_s,
              workflow_definition: workflow_definition,
              goal: goal,
              start_workflow: @start_workflow
            }
          end

          def workload_pipeline
            project.pipelines.find { |pipeline| pipeline[:source] == 'duo_workflow' }
          end

          # Populates #id and #workflow_definition from the most recently created flow in the
          # project.
          #
          # @return [String, nil] the flow id, or nil when the project has no flow yet
          def reload_latest!
            response = process_api_response(
              api_post_to(
                '/graphql',
                <<~GQL
                  query {
                    project(fullPath: "#{project.full_path}") {
                      duoWorkflowWorkflows(first: 1) { nodes { id workflowDefinition } }
                    }
                  }
                GQL
              )
            )

            node = response.dig(:duo_workflow_workflows, :nodes)&.first
            return unless node

            @workflow_definition = node[:workflow_definition]
            @id = node[:id].to_s.split('/').last
          end

          def current_status
            response = process_api_response(
              api_post_to(
                '/graphql',
                <<~GQL
                  query {
                    project(fullPath: "#{project.full_path}") {
                      duoWorkflowWorkflows(workflowId: "gid://gitlab/Ai::DuoWorkflows::Workflow/#{id}") {
                        nodes { statusName }
                      }
                    }
                  }
                GQL
              )
            )

            response.dig(:duo_workflow_workflows, :nodes)&.first&.dig(:status_name)
          end

          private

          def flow_config
            FOUNDATIONAL_FLOWS.fetch(workflow_definition) do
              raise ArgumentError,
                "Unknown foundational flow '#{workflow_definition}'. Add it to " \
                  "#{self.class}::FOUNDATIONAL_FLOWS or set #goal explicitly."
            end
          end
        end
      end
    end
  end
end
