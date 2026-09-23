# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::DuoWorkflows::WorkflowSourceTypeEnum, feature_category: :duo_agent_platform do
  it { expect(described_class.graphql_name).to eq('DuoWorkflowSourceType') }

  # The values are hardcoded, so nothing stops the model and the schema drifting apart.
  it 'exposes every source_type defined on the model' do
    expect(described_class.values.values.map(&:value))
      .to match_array(::Ai::DuoWorkflows::Workflow.source_types.keys)
  end
end
