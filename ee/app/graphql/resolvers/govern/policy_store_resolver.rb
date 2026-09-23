# frozen_string_literal: true

module Resolvers
  module Govern
    # Serves both Group and Organization parents; each model defines its own
    # policy_store_experiment_active? gating (instance-wide checks plus the
    # container's own opt-in setting on both).
    class PolicyStoreResolver < BaseResolver
      type ::Types::Govern::PolicyStoreType, null: true

      def resolve
        object.policy_store_experiment_active? ? object : nil
      end
    end
  end
end
