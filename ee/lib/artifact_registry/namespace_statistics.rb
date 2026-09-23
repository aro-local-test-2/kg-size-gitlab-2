# frozen_string_literal: true

module ArtifactRegistry
  class NamespaceStatistics
    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def repositories_count
      @attributes['repositories_count']
    end

    def deduplicated_size_bytes
      @attributes['deduplicated_size_bytes']
    end
  end
end
