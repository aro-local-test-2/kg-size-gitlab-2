# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::FlowScheduleType, feature_category: :code_suggestions do
  include GraphqlHelpers

  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiFlowScheduleType')
  end

  it 'has the expected fields' do
    expected_fields = %w[
      id
      description
      cron
      cron_timezone
      active
      next_run_at
      last_run
      consecutive_failure_count
      flow_trigger
      project
      created_at
      updated_at
    ]

    expect(described_class.own_fields.size).to eq(expected_fields.size)
    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  it { expect(described_class).to require_graphql_authorizations(:read_ai_flow_triggers) }

  describe '#last_run' do
    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    context 'when the schedule has never run' do
      let_it_be(:schedule) { create(:ai_flow_schedule) }

      it 'returns nil' do
        expect(resolve_field(:last_run, schedule)).to be_nil
      end
    end

    context 'when the schedule has run' do
      let_it_be(:schedule) do
        create(:ai_flow_schedule, last_run_at: Time.current, last_run_status: :success)
      end

      it 'returns the schedule itself' do
        expect(resolve_field(:last_run, schedule)).to eq(schedule)
      end
    end
  end
end
