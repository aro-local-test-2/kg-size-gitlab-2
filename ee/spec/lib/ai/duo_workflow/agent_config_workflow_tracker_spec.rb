# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::AgentConfigWorkflowTracker, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }

  let(:tracker) { described_class.new(project) }
  let(:cache_key) { ['duo_agent_config_workflow', project.id] }

  before do
    allow(Rails.cache).to receive(:read).and_call_original
  end

  describe '#track' do
    it 'writes the workflow id to the cache with a 7-day TTL' do
      workflow = build_stubbed(:duo_workflows_workflow, id: 99)

      expect(Rails.cache).to receive(:write).with(cache_key, 99, expires_in: 7.days)

      tracker.track(workflow)
    end
  end

  describe '#active_workflow' do
    context 'when nothing is tracked' do
      it 'returns nil' do
        expect(tracker.active_workflow).to be_nil
      end
    end

    context 'when the tracked workflow is running' do
      let_it_be(:workflow) { create(:duo_workflows_workflow, :running, project: project) }

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(workflow.id)
      end

      it 'returns the workflow' do
        expect(tracker.active_workflow).to eq(workflow)
      end
    end

    context 'when the tracked workflow has finished' do
      let_it_be(:workflow) { create(:duo_workflows_workflow, :failed, project: project) }

      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(workflow.id)
      end

      it 'returns nil' do
        expect(tracker.active_workflow).to be_nil
      end
    end

    context 'when the cached workflow no longer exists' do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(non_existing_record_id)
      end

      it 'prunes the stale cache entry and returns nil', :aggregate_failures do
        expect(Rails.cache).to receive(:delete).with(cache_key)
        expect(tracker.active_workflow).to be_nil
      end
    end
  end
end
