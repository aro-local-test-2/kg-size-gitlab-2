# frozen_string_literal: true

module ArtifactRegistry
  class MavenPackage
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def group_id
      @attributes['group_id']
    end

    def artifact_id
      @attributes['artifact_id']
    end

    def last_downloaded_at
      parse_time(@attributes['last_downloaded_at'])
    end
  end
end
