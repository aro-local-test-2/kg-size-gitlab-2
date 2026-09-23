# frozen_string_literal: true

module ArtifactRegistry
  class NpmPackage
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def name
      @attributes['name']
    end

    def scope
      @attributes['scope']
    end

    def versions_count
      @attributes['versions_count']
    end

    def last_downloaded_at
      parse_time(@attributes['last_downloaded_at'])
    end
  end
end
