# frozen_string_literal: true

module Ai
  module DuoAgentPlatform
    module AccessPolicy
      extend ActiveSupport::Concern

      included do
        condition(:duo_agent_platform_enabled, scope: :subject) do
          ::Ai::DuoWorkflow.duo_agent_platform_available?(@subject)
        end

        condition(:duo_workflow_available) do
          next false unless user_is_user?

          @subject.duo_features_enabled &&
            ::Gitlab::Llm::StageCheck.available?(@subject, :duo_workflow) &&
            @user.allowed_to_use?(:duo_agent_platform, root_namespace: @subject.root_ancestor)
        end

        # Mirrors the checks of :access_code_suggestions in GlobalPolicy. Project and
        # group policies do not delegate to the global policy, so they need their
        # own copy.
        condition(:code_suggestions_licensed, scope: :global) do
          next true if ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
          next true if ::GitlabSubscriptions::Duo.active_self_managed_gitlab_credits?

          ::License.feature_available?(:code_suggestions)
        end

        # `scope: :user` because the result does not depend on the subject yet.
        # Remove the scope when this passes `root_namespace: @subject.root_ancestor`:
        # https://gitlab.com/gitlab-org/gitlab/-/work_items/628218
        condition(:code_suggestions_enabled_for_user, scope: :user) do
          next false unless @user

          @user.allowed_to_use?(:code_suggestions)
        end
      end
    end
  end
end
