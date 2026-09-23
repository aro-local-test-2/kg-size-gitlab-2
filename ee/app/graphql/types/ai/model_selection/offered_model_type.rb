# frozen_string_literal: true

module Types
  module Ai
    module ModelSelection
      # rubocop: disable Graphql/AuthorizeTypes -- authorization in resolver/mutation
      class OfferedModelType < ::Types::BaseObject
        graphql_name 'AiModelSelectionOfferedModel'
        description 'Model offered for Model Selection'

        include ::Types::Ai::ModelSelection::OfferedModelFields
      end
      # rubocop: enable Graphql/AuthorizeTypes
    end
  end
end
