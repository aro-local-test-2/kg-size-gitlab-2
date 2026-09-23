# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::Widgets::DecisionLogType, feature_category: :team_planning do
  let(:fields) do
    %i[type decisions]
  end

  specify { expect(described_class.graphql_name).to eq('WorkItemWidgetDecisionLog') }

  specify { expect(described_class).to have_graphql_fields(fields) }

  specify do
    expect(described_class.fields['decisions']).to have_graphql_arguments(:states, :after, :before, :first, :last)
  end
end
