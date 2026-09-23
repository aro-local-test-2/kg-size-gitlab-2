# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module RiskClassification
        module Definition
          module_function

          REFERENCE = 'risk_classification/v1'
          private_constant :REFERENCE

          def configuration
            {
              foundational_flow_reference: REFERENCE,
              display_name: s_(
                "FoundationalFlow|Risk Classification"
              ),
              description: s_(
                "FoundationalFlow|Classify the risk of a merge request so review effort can be " \
                  "routed to the changes that warrant it."
              ),
              avatar: "gitlab-duo-flow.png",
              feature_maturity: "experimental",
              ai_feature: "duo_agent_platform",
              environment: "web",
              ultimate_only: true,
              feature_flag: "duo_mr_risk_classification",
              agent_privileges: [
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
              ],
              suppress_agent_session_note: true,
              supported_resource_types: [::MergeRequest],
              triggers: [
                ::Ai::FlowTrigger::EVENT_TYPES[:merge_request]
              ],
              additional_context_resolver: Context,
              before_start: ->(resource:) do
                assessment = ::MergeRequests::RiskAssessment.ensure_for!(resource)
                # enqueue is refused while a run is already queued; touching keeps the
                # timeout counting from this attempt instead of the earlier one's start.
                assessment.enqueue || assessment.touch
              end
            }
          end
        end
      end
    end
  end
end
