# frozen_string_literal: true

module EE
  module Gitlab
    module Ci
      module Components
        module InstancePath
          # Fetches component content without performing user access checks.
          # This method should only be called after authorization has been verified
          # through policy settings (e.g., allows_pipeline_execution_policy_ci_config_access?).
          def fetch_content_for_policy_access
            return unless project
            return unless sha

            instrument(:config_component_fetch_content) do
              fetch_component_content
            end
          end
        end
      end
    end
  end
end
