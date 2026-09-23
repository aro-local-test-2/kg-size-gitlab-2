# frozen_string_literal: true

module ArtifactRegistry
  # A container manifest row from the AR manifests or referrers list. size is easy to misread: a
  # remote (cached) repository reports the manifest payload's own bytes, but a hosted repository
  # reports a push-time manifest-tree total that can double-count blobs shared across manifests.
  class Manifest
    include TimeCoercion

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes['id']
    end

    def digest
      @attributes['digest']
    end

    def media_type
      @attributes['media_type']
    end

    def artifact_type
      @attributes['artifact_type']
    end

    def subject_digest
      @attributes['subject_digest']
    end

    def size
      @attributes['size']
    end

    def created_at
      parse_time(@attributes['created_at'])
    end

    def architecture
      @attributes['architecture']
    end

    def os
      @attributes['os']
    end

    def os_variant
      @attributes['os_variant']
    end

    def tags_count
      @attributes['tags_count']
    end

    def referrers_count
      @attributes['referrers_count']
    end

    def children_count
      @attributes['children_count']
    end

    def tags_preview
      string_list('tags_preview')
    end

    def parents_preview
      string_list('parents_preview')
    end

    # The first ten of the detail's children, each a Hash with a child digest and its platform
    # triple. An entry that is not a Hash or lacks a string digest is dropped, so one malformed row
    # can never null the whole non-null-element GraphQL list.
    def children_preview
      hash_list('children_preview')&.select { |child| child['digest'].is_a?(String) }
    end

    private

    # A present array is served as `[]` when empty, so nil means the key was absent.
    # Filtered to string members so a malformed entry is dropped.
    def string_list(key)
      list = @attributes[key]
      return unless list.is_a?(Array)

      list.grep(String)
    end

    # As string_list, but keeps only Hash members: the shape the platform-child arrays carry.
    def hash_list(key)
      list = @attributes[key]
      return unless list.is_a?(Array)

      list.grep(Hash)
    end
  end
end
