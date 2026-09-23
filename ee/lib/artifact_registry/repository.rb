# frozen_string_literal: true

module ArtifactRegistry
  class Repository
    include TimeCoercion

    attr_reader :permissions

    def initialize(attributes = {}, permissions = nil)
      @attributes = attributes || {}
      @permissions = permissions
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

    def packages?
      Client::PACKAGE_FORMATS.include?(format)
    end

    def images?
      Client::IMAGE_FORMATS.include?(format)
    end

    def npm?
      format == 'npm'
    end

    def kind
      @attributes['kind']
    end

    def hosted?
      kind == 'hosted'
    end

    def remote?
      kind == 'remote'
    end

    def virtual?
      kind == 'virtual'
    end

    def visibility
      @attributes['visibility']
    end

    def description
      @attributes['description']
    end

    def artifacts_count
      @attributes['artifacts_count']
    end

    def downloads_count
      @attributes['downloads_count']
    end

    def size_bytes
      @attributes['size_bytes']
    end

    def created_at
      parse_time(@attributes['created_at'])
    end

    def last_updated_at
      parse_time(@attributes['last_updated_at'])
    end

    def created_by
      @attributes['created_by']
    end

    def updated_by
      @attributes['updated_by']
    end

    def settings
      settings = @attributes['settings']

      settings.is_a?(Hash) ? settings : {}
    end
  end
end
