# frozen_string_literal: true

module ArtifactRegistry
  class UpstreamRepositoryAssociation
    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def position
      @attributes['position']
    end

    def upstream_repository
      summary = @attributes['upstream_repository']

      UpstreamRepositorySummary.new(summary.is_a?(Hash) ? summary : nil)
    end
  end
end
