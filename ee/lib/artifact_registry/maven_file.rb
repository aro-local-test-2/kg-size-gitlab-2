# frozen_string_literal: true

module ArtifactRegistry
  class MavenFile
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

    def sha1
      @attributes['sha1']
    end

    def sha512
      @attributes['sha512']
    end

    # Nullable in the contract: a deploy may store no MD5.
    def md5
      @attributes['md5']
    end

    # Nullable: the Maven file resource may omit the timestamp, so it coerces to nil.
    def created_at
      parse_time(@attributes['created_at'])
    end
  end
end
