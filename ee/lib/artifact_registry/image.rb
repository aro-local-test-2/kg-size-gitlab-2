# frozen_string_literal: true

module ArtifactRegistry
  class Image
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

    def last_downloaded_at
      parse_time(@attributes['last_downloaded_at'])
    end
  end
end
