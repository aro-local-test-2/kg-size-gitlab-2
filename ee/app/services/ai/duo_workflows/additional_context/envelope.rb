# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module AdditionalContext
      # `version` is omitted for flow-owned supplements that predate versioning
      # (see FoundationalFlow#resolve_additional_context_for).
      module Envelope
        def self.wrap(category:, fields:, version: nil)
          envelope = {
            "Category" => category.to_s,
            "Content" => ::Gitlab::Json.dump(fields)
          }
          envelope["metadata"] = { "version" => version } if version

          envelope
        end
      end
    end
  end
end
