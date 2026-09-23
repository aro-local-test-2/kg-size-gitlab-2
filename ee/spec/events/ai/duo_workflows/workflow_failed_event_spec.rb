# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Ai::DuoWorkflows::WorkflowFailedEvent, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow) }

  describe '.build' do
    it 'returns a valid event for a drop', :aggregate_failures do
      event = described_class.build(workflow: workflow, status_event: :drop)

      expect(event.event_category).to eq(:duo_agent_platform)
      expect(event.event_type).to eq(:workflow_failed)
      expect(event.event_data).to eq(workflow_id: workflow.id, status_event: 'drop')
    end

    it 'returns a valid event for a stop' do
      event = described_class.build(workflow: workflow, status_event: :stop)

      expect(event.event_data[:status_event]).to eq('stop')
    end
  end

  it_behaves_like 'a cloud event with schema',
    valid_data: { workflow_id: 1, status_event: 'drop' },
    missing_required: %i[workflow_id status_event],
    invalid_types: { workflow_id: 'not_an_integer', status_event: 'finish' }
end
