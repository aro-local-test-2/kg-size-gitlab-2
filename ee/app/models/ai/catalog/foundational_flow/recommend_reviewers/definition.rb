# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module RecommendReviewers
        module Definition
          module_function

          REFERENCE = 'recommend_reviewers/v1'
          private_constant :REFERENCE

          def configuration
            {
              foundational_flow_reference: REFERENCE,
              display_name: s_(
                "FoundationalFlow|Recommend Reviewers"
              ),
              description: s_(
                "FoundationalFlow|Recommend reviewers for merge requests based on availability, " \
                  "workload, and timezone."
              ),
              feature_maturity: "beta",
              avatar: "gitlab-duo-flow.png",
              agent_privileges: [
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
              ],
              triggers: [],
              # The agent session system notes already link the session, so the
              # progress note only adds noise.
              suppress_progress_note: true,
              flow_version_resolver: ->(container:, user:) do
                [REFERENCE, '^3.0.0'] if ::Feature.enabled?(:recommend_reviewers_flow_v3, container)
              end,
              # Default (non-v3) flow config version. See recommend_reviewers/2.0.0.yml
              # in the ai-assist repo, which reads agent_platform_recommend_reviewers_context.
              flow_version: '2.0.0',
              supported_resource_types: [::MergeRequest],
              goal_templates: ::Ai::Catalog::GoalTemplates::RecommendReviewers,
              noteable_resolver: ->(project:, goal:) { project.merge_requests.find_by_iid(goal) },
              additional_context_resolver: ->(resource:) do
                data = ::Ai::DuoWorkflows::RecommendReviewers::ReviewerDataBuilder.build(resource)

                # Dual-emit: legacy category kept until DWS migrates to the typed envelope.
                {
                  "reviewer_data" => data,
                  "agent_platform_recommend_reviewers_context" => data
                }
              end
            }
          end
        end
      end
    end
  end
end
