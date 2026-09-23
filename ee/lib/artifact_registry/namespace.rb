# frozen_string_literal: true

module ArtifactRegistry
  # Value object for a namespace returned by the AR GitLab API
  # (GET /api/gitlab/v1/namespaces/:uuid). `id` is AR's namespace UUID.
  # `status` is passed through raw and unvalidated so unrecognized values
  # reach the frontend's fallback instead of raising.
  class Namespace
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def slug
      @attributes['slug']
    end

    def platform
      @attributes['platform']
    end

    def entity_type
      @attributes['entity_type']
    end

    def entity_id
      @attributes['entity_id']
    end

    def status
      @attributes['status']
    end

    def created_at
      parse_time(@attributes['created_at'])
    end
  end
end
