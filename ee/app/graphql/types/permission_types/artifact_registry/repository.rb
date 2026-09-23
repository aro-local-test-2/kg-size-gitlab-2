# frozen_string_literal: true

module Types
  module PermissionTypes
    module ArtifactRegistry
      # rubocop: disable Graphql/AuthorizeTypes -- inherited from Base's
      # `authorize :read_artifact_registry`; the cop reads only this class body
      class Repository < Base
        graphql_name 'ArtifactRegistryRepositoryPermissions'
        description 'Per-action permissions Artifact Registry reports for the current user on a repository.'

        DESCRIPTIONS = {
          'read_repository' => 'Indicates the user can read the repository and its metadata.',
          'update_repository' => "Indicates the user can change the repository's settings.",
          'delete_repository' => 'Indicates the user can delete the repository.',
          'create_repository_upstream' => 'Indicates the user can add an upstream to the repository.',
          'update_repository_upstream' => 'Indicates the user can change an upstream of the repository.',
          'delete_repository_upstream' => 'Indicates the user can remove an upstream from the repository.',
          'read_artifact' => 'Indicates the user can read artifacts held by the repository.',
          'create_artifact' => 'Indicates the user can publish artifacts to the repository.',
          'delete_artifact' => 'Indicates the user can delete artifacts from the repository.'
        }.freeze

        ::ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.each do |action|
          verdict_field action,
            experiment: { milestone: '19.5' },
            description: DESCRIPTIONS.fetch(action)
        end
      end
      # rubocop: enable Graphql/AuthorizeTypes
    end
  end
end
