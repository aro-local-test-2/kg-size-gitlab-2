# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::DecisionOptionType, feature_category: :team_planning do
  let(:fields) do
    %i[id content description recommended selected]
  end

  specify { expect(described_class.graphql_name).to eq('WorkItemDecisionOption') }

  specify { expect(described_class).to have_graphql_fields(fields) }
end
