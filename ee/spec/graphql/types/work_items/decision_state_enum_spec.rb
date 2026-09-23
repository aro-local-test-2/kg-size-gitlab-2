# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::DecisionStateEnum, feature_category: :team_planning do
  specify { expect(described_class.graphql_name).to eq('WorkItemDecisionState') }

  it 'exposes every model state' do
    expect(described_class.values.keys).to contain_exactly('ACTIVE', 'RESOLVED', 'ARCHIVED')
    expect(described_class.values.values.map(&:value)).to contain_exactly(:active, :resolved, :archived)
  end
end
