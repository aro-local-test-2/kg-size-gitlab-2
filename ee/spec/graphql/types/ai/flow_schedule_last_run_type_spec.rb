# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::FlowScheduleLastRunType, feature_category: :code_suggestions do
  include GraphqlHelpers

  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiFlowScheduleLastRun')
  end

  it 'has the expected fields' do
    expected_fields = %w[
      ran_at
      status
      error
    ]

    expect(described_class.own_fields.size).to eq(expected_fields.size)
    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  describe 'field resolution' do
    let_it_be(:schedule) do
      create(:ai_flow_schedule,
        last_run_at: Time.current,
        last_run_status: :execution_error,
        last_run_error: 'boom')
    end

    it 'reads the last run attributes from the schedule' do
      expect(resolve_field(:ran_at, schedule)).to be_like_time(schedule.last_run_at)
      expect(resolve_field(:status, schedule)).to eq('execution_error')
      expect(resolve_field(:error, schedule)).to eq('boom')
    end
  end
end
