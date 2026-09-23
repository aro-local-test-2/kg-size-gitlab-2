# frozen_string_literal: true

module Authz
  module ArtifactRegistry
    # Resolves Artifact Registry role names to and from their glaz-roles ids
    # via Gitlab::Glaz.roles (gitlab-glaz >= 1.1.0), which exposes only a
    # display `name` and `id`, not the machine-readable `key` - hence NAMES.
    module Roles
      require 'gitlab/glaz'

      NAMES = {
        artifact_viewer: 'Artifact Viewer',
        artifact_contributor: 'Artifact Contributor',
        artifact_manager: 'Artifact Manager',
        artifact_admin: 'Artifact Admin',
        # Platform role, not one of the four AR roles above - inherits
        # artifact_admin's full permission set (roles/organization_admin.yml).
        organization_admin: 'Organization Administrator'
      }.freeze

      def self.uuid_for(role_name)
        name = NAMES[role_name.downcase.to_sym]
        return unless name

        ids_by_name[name]
      end

      def self.name_for(role_id)
        NAMES.key(names_by_id[role_id])
      end

      def self.ids_by_name
        @ids_by_name ||= ::Gitlab::Glaz.roles.to_h { |role| [role[:name], role[:id]] }
      end
      private_class_method :ids_by_name

      def self.names_by_id
        @names_by_id ||= ::Gitlab::Glaz.roles.to_h { |role| [role[:id], role[:name]] }
      end
      private_class_method :names_by_id
    end
  end
end
