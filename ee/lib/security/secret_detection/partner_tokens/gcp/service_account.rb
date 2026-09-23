# frozen_string_literal: true

module Security
  module SecretDetection
    module PartnerTokens
      module Gcp
        # Placeholder verifier for GCP service account keys (JSON private key).
        #
        # Real verification means parsing the JSON blob, signing a JWT with the
        # private key, and exchanging it at the OAuth token endpoint. Until that
        # flow ships, findings stay unknown. See
        # https://gitlab.com/gitlab-org/gitlab/-/work_items/588454.
        class ServiceAccount < Base
          private

          # Not a ruleset re-check: the JWT verification flow does not exist yet,
          # so the gate keeps every finding on the unknown path without a vendor
          # call.
          def valid_format?(_token_value)
            false
          end
        end
      end
    end
  end
end
