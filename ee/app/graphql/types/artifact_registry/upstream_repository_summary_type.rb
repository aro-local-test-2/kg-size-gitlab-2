# frozen_string_literal: true

module Types
  module ArtifactRegistry
    class UpstreamRepositorySummaryType < BaseObject
      graphql_name 'ArtifactRegistryUpstreamRepositorySummary'
      description 'Summary of a repository that is an upstream of a virtual Artifact Registry repository.'

      authorize :read_artifact_registry

      include ::ArtifactRegistry::ExposesElementId

      # Derived from the enum so a kind added there cannot start raising here as unsupported.
      CONTRACT_KINDS = ::Types::ArtifactRegistry::UpstreamRepositoryKindEnum
        .values.values.map(&:value).freeze

      exposes_element_id noun: 'upstream repository', milestone: '19.5'

      authorize_granular_token skip_reason: :parent_authorizes

      field :name, GraphQL::Types::String,
        null: false,
        experiment: { milestone: '19.5' },
        description: 'Name of the upstream repository.'

      field :format, ::Types::ArtifactRegistry::RepositoryFormatEnum,
        null: false,
        experiment: { milestone: '19.5' },
        description: 'Package format the upstream repository holds.'

      field :kind, ::Types::ArtifactRegistry::UpstreamRepositoryKindEnum,
        null: true,
        experiment: { milestone: '19.5' },
        description: 'How the upstream repository sources its artifacts. ' \
          'Artifact Registry returns `hosted` or `remote` by contract; a value outside those ' \
          'resolves `null` alongside a top-level error rather than a badge.'

      def kind
        raw = object.kind
        return raw if CONTRACT_KINDS.include?(raw)

        # `kind` is required by contract, so a missing one is as much a breach as an unknown one.
        raise ::Gitlab::Graphql::Errors::BaseError,
          "Artifact Registry returned an unsupported upstream kind: #{raw.presence || 'none'}."
      end
    end
  end
end
