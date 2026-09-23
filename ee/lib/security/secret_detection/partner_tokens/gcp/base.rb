# frozen_string_literal: true

module Security
  module SecretDetection
    module PartnerTokens
      module Gcp
        # Shared vendor identity for the GCP token verifiers. The three GCP token
        # types authenticate against different surfaces, so there is no shared
        # request shape here, only the metrics label.
        class Base < BaseClient
          private

          # Every subclass demodulizes to its own token type, so the vendor label
          # is pinned here to keep `partner` a per-vendor axis.
          def partner_name
            'gcp'
          end
        end
      end
    end
  end
end
