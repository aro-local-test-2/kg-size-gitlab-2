# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module RiskClassification
        module Context
          module_function

          CONTEXT_CATEGORY = 'agent_platform_risk_classification_context'
          private_constant :CONTEXT_CATEGORY

          def call(resource:) # rubocop:disable Lint/UnusedMethodArgument -- kept to match validation
            domains = ::Gitlab::Duo::RiskClassification::Domain.all.map do |domain|
              { "name" => domain.name, "description" => domain.description }
            end

            {
              CONTEXT_CATEGORY => { "domains" => domains }
            }
          end
        end
      end
    end
  end
end
