# frozen_string_literal: true

module Gitlab
  module Duo
    module RiskClassification
      module Signals
        # Whether the change ships behind a feature flag.
        #
        # A mitigation, not a risk: a flagged change can be turned off without
        # a revert, so it is not as exposed as the same change shipped
        # unguarded. Detection is the flag definition file rather than
        # Feature.enabled? call sites, which would mean reading every changed
        # file to find them.
        class RolloutGuard < Base
          set_label N_('RiskClassification|Feature flag rollout')

          add_dimension :feature_flag, N_('RiskClassification|Change ships behind a feature flag')

          FLAG_DEFINITION = %r{\A(ee/|jh/)?config/feature_flags/.+\.ya?ml\z}

          mitigation!

          def available?
            changed_paths.present?
          end

          def feature_flag
            flag_defined? ? 1.0 : 0.0
          end

          private

          def flag_defined?
            changed_paths.any? { |path| path.match?(FLAG_DEFINITION) }
          end
        end
      end
    end
  end
end
