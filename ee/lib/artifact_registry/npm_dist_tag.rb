# frozen_string_literal: true

module ArtifactRegistry
  # `version` is a denormalized version string (e.g. '1.10.0'), not an ArtifactRegistry::Version
  # and distinct from `version_id`; the tag is mutable, so both track whatever version it now names.
  class NpmDistTag
    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def name
      @attributes['name']
    end

    def version_id
      @attributes['version_id']
    end

    def version
      @attributes['version']
    end
  end
end
