# frozen_string_literal: true

module ArtifactRegistry
  class UpstreamRepositorySummary
    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def name
      @attributes['name']
    end

    def format
      @attributes['format']
    end

    def kind
      @attributes['kind']
    end
  end
end
