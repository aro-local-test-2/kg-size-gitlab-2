# frozen_string_literal: true

module ArtifactRegistry
  # `permissions` is nil when not requested, an absent `Verdicts` when requested
  # but not served, or populated when served.
  class NamespaceDetails
    include TimeCoercion

    attr_reader :permissions

    def initialize(attributes = {}, permissions = nil)
      @attributes = attributes || {}
      @permissions = permissions
    end

    def slug
      @attributes['slug']
    end

    def created_at
      parse_time(@attributes['created_at'])
    end
  end
end
