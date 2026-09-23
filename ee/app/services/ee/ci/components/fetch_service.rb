# frozen_string_literal: true

module EE
  module Ci
    module Components
      module FetchService
        extend ::Gitlab::Utils::Override

        override :handle_access_denied_error
        def handle_access_denied_error
          if pipeline_execution_policy_component_access_allowed?
            fetch_content_with_policy_access
          else
            super
          end
        end

        private

        def pipeline_execution_policy_component_access_allowed?
          return false unless current_user.security_policy_bot?
          return false unless policy_management_project_access_allowed?
          return false unless target_project
          return false unless component_path
          return false unless component_path.project

          component_file_paths.any? do |file_path|
            ::Gitlab::SafeRequestStore.fetch(
              [
                'Ci::Components::FetchService',
                'pipeline_execution_policy_component_access_allowed',
                component_path.project.id,
                target_project.id,
                file_path
              ]
            ) do
              component_path.project.project_setting.allows_pipeline_execution_policy_ci_config_access?(
                file_path: file_path,
                requesting_project: target_project
              )
            end
          end
        end

        def target_project
          pipeline_policy_context&.pipeline_execution_context&.target_project || requesting_project
        end

        def policy_management_project_access_allowed?
          pipeline_policy_context&.pipeline_execution_context&.policy_management_project_access_allowed?
        end

        def component_file_paths
          component_path.template_file_paths
        end

        def fetch_content_with_policy_access
          result = component_path.fetch_content_for_policy_access

          if result&.content
            ServiceResponse.success(payload: {
              content: result.content,
              path: result.path,
              project: component_path.project,
              sha: component_path.sha,
              name: component_path.component_name,
              version: component_path.matched_version,
              reference: component_path.reference
            })
          else
            ServiceResponse.error(message: "#{error_prefix} content not found", reason: :content_not_found)
          end
        end
      end
    end
  end
end
