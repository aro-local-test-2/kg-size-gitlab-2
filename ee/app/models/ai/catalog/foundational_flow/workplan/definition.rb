# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module Workplan
        module Definition
          module_function

          REFERENCE = 'workplan/v1'
          private_constant :REFERENCE

          # The workplan goal is the full prompt with the work item URL embedded, so
          # resolve the work item from that URL to link the flow session to it.
          NOTEABLE_RESOLVER = ->(project:, goal:) do
            iid = goal.to_s.match(%r{/-/(?:work_items|issues)/(\d+)})&.captures&.first&.to_i
            next unless iid&.positive?

            project.work_items.find_by_iid(iid)
          end
          private_constant :NOTEABLE_RESOLVER

          def configuration
            {
              foundational_flow_reference: REFERENCE,
              display_name: s_(
                "FoundationalFlow|Generate Workplan"
              ),
              description: s_(
                "FoundationalFlow|Draft a Why/How/What workplan for a work item and write it to the " \
                  "Workplan widget."
              ),
              avatar: "gitlab-duo-flow.png",
              feature_maturity: "experimental",
              feature_flag: "duo_workplan_async_flow",
              # Runs server-side (CI-backed) so the plan is generated asynchronously without
              # opening Duo Chat. Mirrors the Planner chat agent's GitLab-only tool needs
              # (read/update work items), so no file, git, or command privileges are granted.
              # START_FLOWS is also needed so the workplan flow can start the
              # readiness_score/v1 scoring flow as a child flow.
              agent_privileges: [
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
              ],
              environment: "web",
              triggers: [],
              supported_events: [],
              goal_templates: ::Ai::Catalog::GoalTemplates::Workplan,
              noteable_resolver: NOTEABLE_RESOLVER
            }
          end
        end
      end
    end
  end
end
