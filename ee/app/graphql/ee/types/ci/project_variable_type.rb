# frozen_string_literal: true

module EE
  module Types
    module Ci
      module ProjectVariableType
        extend ActiveSupport::Concern
        extend ::Gitlab::Utils::Override

        override :value
        def value
          record_value_access

          super
        end

        private

        def record_value_access
          return unless ::Feature.enabled?(:audit_ci_variable_value_access, current_user)

          scope = variable_scope
          return unless scope

          ::Gitlab::Ci::Variables::AccessCollector
            .for(context)
            .record(scope: scope, key: object.key, hidden: object.hidden?)
        end

        def variable_scope
          object.project
        end
      end
    end
  end
end
