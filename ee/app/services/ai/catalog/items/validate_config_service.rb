# frozen_string_literal: true

module Ai
  module Catalog
    module Items
      class ValidateConfigService
        def initialize(project:, current_user:)
          @project = project
          @current_user = current_user
        end

        def execute(definition_hash)
          config = definition_hash&.except('yaml_definition')
          dws_client.validate_flow_config(flow_config: config)
        end

        private

        attr_reader :project, :current_user

        def dws_client
          feature_setting = resolve_feature_setting

          ::Ai::DuoWorkflow::DuoWorkflowService::Client.new(
            duo_workflow_service_url: ::Gitlab::DuoWorkflow::Client.url_for(
              feature_setting: feature_setting, user: current_user
            ),
            current_user: current_user,
            secure: ::Gitlab::DuoWorkflow::Client.secure?(feature_setting: feature_setting),
            container: project
          )
        end

        def resolve_feature_setting
          ::Ai::FeatureSettingSelectionService.new(
            current_user,
            ::Ai::ModelSelection::FeaturesConfigurable.workflow_feature_name,
            project.root_ancestor
          ).execute.payload
        end
      end
    end
  end
end
