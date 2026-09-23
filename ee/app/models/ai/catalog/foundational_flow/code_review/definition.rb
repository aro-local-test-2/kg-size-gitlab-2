# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module CodeReview
        module Definition
          module_function

          REFERENCE = 'code_review/v1'
          DEEP_REFERENCE = 'deep_code_review/v1'
          private_constant :REFERENCE, :DEEP_REFERENCE

          # Accepts a bare IID or a same-project MR URL, tolerating suffixes from
          # browser-copied URLs (/diffs, ?query, #note anchors).
          MERGE_REQUEST_RESOLVER = ->(project:, goal:) do
            goal = goal.to_s.strip
            iid = if /\A\d+\z/.match?(goal)
                    goal
                  else
                    project_url = ::Gitlab::Routing.url_helpers.project_url(project)
                    goal[%r{\A#{Regexp.escape(project_url)}/-/merge_requests/(\d+)(?:[/?#]|\z)}, 1]
                  end

            project.merge_requests.find_by_iid(iid) if iid
          end
          private_constant :MERGE_REQUEST_RESOLVER

          def configuration
            {
              foundational_flow_reference: REFERENCE,
              display_name: s_(
                "FoundationalFlow|Code Review"
              ),
              description: s_(
                "FoundationalFlow|Streamline code reviews by analyzing code changes and relevant " \
                  "codebase context. " \
                  "[How can I use this flow](https://docs.gitlab.com/user/duo_agent_platform/flows/foundational_flows/code_review/#use-the-flow)?"
              ),
              avatar: "code-review-flow.png",
              feature_maturity: "ga",
              ai_feature: "review_merge_request_dap",
              agent_privileges: [
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT,
                ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES
              ],
              # Code Review posts its own progress note when a review starts, so it
              # opts out of the generic agent-session-started system note.
              suppress_agent_session_note: true,
              # Code Review sets the goal to the merge request iid, so the noteable
              # resolves to that merge request and the session links to it.
              noteable_resolver: MERGE_REQUEST_RESOLVER,
              # The flow resolves its target MR with find_by_iid(goal), so anything
              # else fails only after the LLM steps have run and been billed. Reject
              # invalid goals upfront and normalize URL goals to a bare IID.
              goal_validator_resolver: ->(container:, goal:) do
                unless container.is_a?(Project)
                  next ServiceResponse.error(
                    message: 'Code reviews require a project context',
                    reason: :invalid_goal
                  )
                end

                merge_request = MERGE_REQUEST_RESOLVER.call(project: container, goal: goal)

                unless merge_request
                  next ServiceResponse.error(
                    message: 'The goal for code reviews must be a merge request IID or a full merge request URL',
                    reason: :invalid_goal
                  )
                end

                ServiceResponse.success(payload: { goal: merge_request.iid.to_s })
              end,
              triggers: [],
              flow_version_resolver: ->(container:, user:) do
                if ::Feature.enabled?(:duo_code_review_deep_flow, user)
                  [DEEP_REFERENCE, '1.0.0']
                elsif ::Feature.enabled?(:duo_code_review_previous_discussions, user)
                  [REFERENCE, '^2.0.0']
                end
              end,
              # Code Review posts its comments as this bot, not as the flow's service
              # account, so the flow cannot use service_account_name to recognise them.
              additional_context_resolver: ->(resource:) do
                next {} unless resource.is_a?(::MergeRequest)

                review_bot = ::Users::Internal
                  .in_organization(resource.project.organization_id)
                  .duo_code_review_bot

                {
                  "code_review_context" => {
                    "duo_code_review_bot_name" => review_bot&.username,
                    "last_reviewed_head_sha" => resource.duo_code_review_last_reviewed_head_sha(review_bot)
                  }.compact
                }
              end
            }
          end
        end
      end
    end
  end
end
