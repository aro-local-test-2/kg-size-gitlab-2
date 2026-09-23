# frozen_string_literal: true

module ArtifactRegistry
  class Version
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def version
      @attributes['version']
    end

    def created_at
      parse_time(@attributes['created_at'])
    end

    # AR's three publish-attribution references pass through raw and unresolved;
    # the GraphQL resolver performs the cross-service join.
    def created_by
      @attributes['created_by']
    end

    def project_id
      @attributes['project_id']
    end

    def git_commit_sha
      @attributes['git_commit_sha']
    end

    def dist_tags
      tags = @attributes['dist_tags']

      tags.is_a?(Array) ? tags.grep(String) : []
    end

    # Required in the contract, so nil here is an explicit JSON null (a remote version, or a Maven
    # version pending #550), never an omitted key. Coerced to an Integer so a string or float from
    # AR cannot reach BigInt's `to_s` coercion and render a non-numeric sizeBytes. Routed through
    # Float first so a numeric string and a float truncate alike ("123.9" and 123.9 both to 123),
    # rather than the string dropping to nil while the float truncates.
    def size
      value = @attributes['size']
      return if value.nil?

      float = Float(value, exception: false)
      Integer(float) unless float.nil?
    end

    # nil when absent lets the resolver's pairing check tell "not serialized" from "different
    # artifact". The wire key is unconfirmed: the contract carries no version-level package_id yet
    # (AR serialization gate), so this reads nil until that patch lands. Coerced to a String so a
    # numeric wire value compares against the coerced GraphQL ID argument rather than failing the
    # pairing check for every version.
    def package_id
      @attributes['package_id']&.to_s
    end

    # The filtered package.json projection, passed through as a Hash. The wire key is unconfirmed
    # (the npm metadata projection is a deferred AR gate), so this reads nil until it lands. A
    # non-Hash coerces to nil so a malformed value cannot reach the resolver as another shape.
    def npm_metadata
      metadata = @attributes['npm_metadata']

      metadata if metadata.is_a?(Hash)
    end
  end
end
