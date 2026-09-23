# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::IncrementalBlobGate, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:incremental_checkpoints_enabled) { true }
  let(:workflow) do
    create(:duo_workflows_workflow, project: project,
      incremental_checkpoints_enabled: incremental_checkpoints_enabled)
  end

  subject(:gate) { described_class.new(workflow) }

  describe '#reconstruct?' do
    subject { gate.reconstruct? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project)
    end

    it { is_expected.to be(true) }

    context 'when the read flag is off' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the read flag is enabled for the root ancestor only' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: group)
      end

      it { is_expected.to be(true) }
    end

    context 'when the workflow does not have incremental checkpoints enabled' do
      let(:incremental_checkpoints_enabled) { false }

      it { is_expected.to be(false) }
    end

    context 'when the workflow has no resource_parent' do
      before do
        allow(workflow).to receive(:resource_parent).and_return(nil)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#read?' do
    subject { gate.read? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project)
    end

    context 'when the newest header records its channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: [])
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2',
          channel_keys: %w[status ui_chat_log])
      end

      it { is_expected.to be(true) }
    end

    context 'when the newest header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: nil)
      end

      it { is_expected.to be(false) }
    end

    # Only the newest header is checked, so a time-travel read of the older one folds
    # without a membership. Accepted: those headers age out with their partition.
    context 'when an older header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: nil)
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2', channel_keys: %w[status])
      end

      it { is_expected.to be(true) }
    end

    context 'when the workflow has no headers' do
      it { is_expected.to be(true) }
    end

    context 'when the read flag is off' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#for_notifications?' do
    subject { gate.for_notifications? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_notifications: project)
    end

    it { is_expected.to be(true) }

    context 'when the notifications flag is enabled for the root ancestor only' do
      before do
        stub_feature_flags(dw_read_blobs_notifications: group)
      end

      it { is_expected.to be(true) }
    end

    context 'when the notifications flag is off' do
      before do
        stub_feature_flags(dw_read_blobs_notifications: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the base gate is closed' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#for_list?' do
    subject { gate.for_list? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_list: project)
    end

    it { is_expected.to be(true) }

    context 'when the list flag is enabled for the root ancestor only' do
      before do
        stub_feature_flags(dw_read_blobs_list: group)
      end

      it { is_expected.to be(true) }
    end

    context 'when the list flag is off' do
      before do
        stub_feature_flags(dw_read_blobs_list: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the base gate is closed' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#for_graphql?' do
    subject { gate.for_graphql? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_graphql: project)
    end

    it { is_expected.to be(true) }

    context 'when the graphql flag is enabled for the root ancestor only' do
      before do
        stub_feature_flags(dw_read_blobs_graphql: group)
      end

      it { is_expected.to be(true) }
    end

    context 'when the graphql flag is off' do
      before do
        stub_feature_flags(dw_read_blobs_graphql: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the base gate is closed' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#graphql_candidate?' do
    subject { gate.graphql_candidate? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_graphql: project)
    end

    it { is_expected.to be(true) }

    context 'when the newest header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, project: project, channel_keys: nil)
      end

      # The candidate check does not read the header, so it stays true here.
      it { is_expected.to be(true) }

      it 'is excluded by #for_graphql?' do
        expect(gate.for_graphql?).to be(false)
      end
    end

    context 'when the graphql flag is off' do
      before do
        stub_feature_flags(dw_read_blobs_graphql: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the base gate is closed' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#for_trace?' do
    subject { gate.for_trace? }

    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
    end

    it { is_expected.to be(true) }

    context 'when the trace flag is enabled for the root ancestor only' do
      before do
        stub_feature_flags(dw_read_blobs_trace: group)
      end

      it { is_expected.to be(true) }
    end

    context 'when the trace flag is off' do
      before do
        stub_feature_flags(dw_read_blobs_trace: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the base gate is closed' do
      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
      end

      it { is_expected.to be(false) }
    end
  end

  # #read? asks legacy_checkpoint_fallback? for the newest header, so the consumer flag
  # has to be checked first or a disabled consumer pays for a query it discards.
  describe 'consumer flag ordering' do
    before do
      stub_feature_flags(duo_workflow_read_incremental_checkpoints: project)
      gate # build outside the recorder so the constructor's parent lookups do not count
    end

    it 'skips the header query when the consumer flag is off' do
      stub_feature_flags(dw_read_blobs_graphql: false)

      recorder = ActiveRecord::QueryRecorder.new { gate.for_graphql? }

      expect(recorder.log).not_to include(a_string_matching(/checkpoint_headers/))
    end

    it 'runs the header query when the consumer flag is on' do
      stub_feature_flags(dw_read_blobs_graphql: project)

      recorder = ActiveRecord::QueryRecorder.new { gate.for_graphql? }

      expect(recorder.log).to include(a_string_matching(/checkpoint_headers/))
    end
  end

  # Feature flags default to enabled in specs, so what #read? checks is the only thing
  # left that can close a gate. Reflecting over every for_*? method fails a new gate
  # that skips #read?, which would read nothing or fold a stale channel set.
  describe 'the shared read gate' do
    consumer_gates = described_class.public_instance_methods(false).grep(/\Afor_\w+\?\z/)

    it 'covers every consumer gate' do
      expect(consumer_gates).to match_array(%i[for_notifications? for_list? for_graphql? for_trace?])
    end

    context 'when the workflow was created with incremental checkpoints' do
      consumer_gates.each do |consumer_gate|
        it "##{consumer_gate} is true" do
          expect(gate.public_send(consumer_gate)).to be(true)
        end
      end
    end

    context 'when the workflow was not created with incremental checkpoints' do
      let(:incremental_checkpoints_enabled) { false }

      consumer_gates.each do |consumer_gate|
        it "##{consumer_gate} is false" do
          expect(gate.public_send(consumer_gate)).to be(false)
        end
      end
    end

    context 'when the newest header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: nil)
      end

      consumer_gates.each do |consumer_gate|
        it "##{consumer_gate} is false" do
          expect(gate.public_send(consumer_gate)).to be(false)
        end
      end
    end

    # The consumer flag runs before #read?, so a nil parent reaches Feature.enabled?.
    context 'when the workflow has no resource_parent' do
      before do
        allow(workflow).to receive(:resource_parent).and_return(nil)
      end

      consumer_gates.each do |consumer_gate|
        it "##{consumer_gate} is false" do
          expect(gate.public_send(consumer_gate)).to be(false)
        end
      end
    end
  end
end
