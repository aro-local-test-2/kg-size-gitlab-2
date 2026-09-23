# frozen_string_literal: true

module ArtifactRegistry
  class NpmFile
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def file_name
      @attributes['file_name']
    end

    def size
      @attributes['size']
    end

    def sha256
      @attributes['sha256']
    end

    # Nullable: the contract serializes it on a hosted row and null on a remote
    # cached one, which carries no per-file time of its own.
    def created_at
      parse_time(@attributes['created_at'])
    end
  end
end
