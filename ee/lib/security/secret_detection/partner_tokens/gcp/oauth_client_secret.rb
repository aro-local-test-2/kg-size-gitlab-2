# frozen_string_literal: true

module Security
  module SecretDetection
    module PartnerTokens
      module Gcp
        # Placeholder verifier for GCP OAuth client secrets (GOCSPX-...).
        #
        # A client secret only authenticates together with its paired client id,
        # which detection does not capture, so there is nothing to send to Google.
        # Findings stay unknown. See
        # https://gitlab.com/gitlab-org/gitlab/-/work_items/588454.
        class OauthClientSecret < Base
          private

          # Not a ruleset re-check: this type cannot be verified at all, so the
          # gate keeps every finding on the unknown path without a vendor call.
          def valid_format?(_token_value)
            false
          end
        end
      end
    end
  end
end
