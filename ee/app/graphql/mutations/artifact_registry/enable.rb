# frozen_string_literal: true

module Mutations
  module ArtifactRegistry
    # Enables an organization's registry through Artifact Registry's enable
    # condition endpoint.
    class Enable < ConditionMutation
      graphql_name 'ArtifactRegistryEnable'
      description 'Enables Artifact Registry for the organization resolved from the ' \
        'request context (the X-GitLab-Organization-ID header, or the user default organization).'

      condition :enable_namespace
    end
  end
end
