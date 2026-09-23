# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module AdditionalContext
      # Builds secret_detection_context envelopes for secrets_fp_detection/v1.
      # Returns an array of two envelopes (legacy + typed) or nil when the finding
      # has no usable secret. Dual-emit kept until DWS migrates to the typed envelope.
      module SecretDetectionContextBuilder
        LEGACY_CATEGORY = "secret_detection_context"
        CATEGORY = "agent_platform_secrets_fp_detection_context"

        # nil when the finding has no usable secret (redacted, or no token value).
        def self.build(vulnerability)
          return if vulnerability.finding&.secret_redacted?

          raw_value = vulnerability.finding&.token_value
          return if raw_value.blank?

          fields = { "secret_value" => raw_value }

          [
            ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: LEGACY_CATEGORY, fields: fields),
            ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(category: CATEGORY, fields: fields)
          ]
        end
      end
    end
  end
end
