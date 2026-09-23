# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Ai::DuoWorkflows::WorkflowApprovalRequiredEvent, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow) }

  describe '.build' do
    it 'returns a valid event', :aggregate_failures do
      event = described_class.build(workflow: workflow)

      expect(event.event_category).to eq(:duo_agent_platform)
      expect(event.event_type).to eq(:workflow_approval_required)
      expect(event.event_data).to eq(workflow_id: workflow.id)
    end
  end

  it_behaves_like 'a cloud event with schema',
    valid_data: { workflow_id: 1 },
    missing_required: %i[workflow_id],
    invalid_types: { workflow_id: 'not_an_integer' }
end
