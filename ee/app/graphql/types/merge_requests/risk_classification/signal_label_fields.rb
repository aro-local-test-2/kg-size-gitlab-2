# frozen_string_literal: true

module Types
  module MergeRequests
    module RiskClassification
      # Shared by ContributingSignalType and MissingSignalType, the only
      # fields the two have in common.
      module SignalLabelFields
        extend ActiveSupport::Concern

        included do
          field :signal, GraphQL::Types::String,
            null: false,
            hash_key: 'signal',
            scopes: [:api, :read_api, :ai_workflows],
            description: 'Name of the signal or claim.'

          field :label, GraphQL::Types::String,
            null: true,
            scopes: [:api, :read_api, :ai_workflows],
            description: 'Human-readable name of the signal. Null for a claim, which has no ' \
              'registered signal class to look one up from.'

          def label
            ::Gitlab::Duo::RiskClassification::SignalsExtractor.label_for(object['signal'])
          end
        end
      end
    end
  end
end
