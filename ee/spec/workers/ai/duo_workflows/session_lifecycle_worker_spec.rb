# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionLifecycleWorker, feature_category: :duo_agent_platform do
  let(:event) { Ai::DuoWorkflows::WorkflowStartedEvent.new(data: { workflow_id: 1 }) }

  describe '#handle_event' do
    it 'does nothing' do
      expect { consume_event(subscriber: described_class, event: event) }.not_to raise_error
    end
  end

  it_behaves_like 'an idempotent worker'
end
