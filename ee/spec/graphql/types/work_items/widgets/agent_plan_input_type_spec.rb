# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Types::WorkItems::Widgets::AgentPlanInputType, feature_category: :team_planning do
  it { expect(described_class.graphql_name).to eq('WorkItemWidgetAgentPlanInput') }

  it 'exposes content, readinessScore, and readinessScoreFeedback arguments' do
    expect(described_class.arguments.keys)
      .to contain_exactly('content', 'readinessScore', 'readinessScoreFeedback')
  end
end
