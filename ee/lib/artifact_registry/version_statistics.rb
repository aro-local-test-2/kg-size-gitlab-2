# frozen_string_literal: true

module ArtifactRegistry
  class VersionStatistics
    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def files_count
      @attributes['files_count']
    end
  end
end
