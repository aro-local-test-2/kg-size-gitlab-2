# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::PendingToolApproval, feature_category: :duo_agent_platform do
  let(:issue_request) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01issue',
      'content' => 'Tool create_issue requires approval',
      'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report' } }
    }
  end

  let(:mr_request) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01mr',
      'content' => 'Tool create_merge_request requires approval',
      'tool_info' => { 'name' => 'create_merge_request', 'args' => { 'title' => 'Fix' } }
    }
  end

  describe '.for' do
    let(:workflow) { instance_double(Ai::DuoWorkflows::Workflow, latest_ui_chat_log: ui_chat_log) }

    subject(:pending) { described_class.for(workflow) }

    context 'when the log ends with a single approval request' do
      let(:ui_chat_log) do
        [
          { 'message_type' => 'agent', 'content' => 'Working on it' },
          issue_request
        ]
      end

      it 'wraps the request' do
        expect(pending.calls).to eq([{
          name: 'create_issue',
          content: 'Tool create_issue requires approval',
          args: { 'title' => 'Bug report' }
        }])
      end
    end

    context 'when the log ends with a run of approval requests' do
      let(:ui_chat_log) do
        [
          { 'message_type' => 'request', 'message_id' => 'toolu_00', 'tool_info' => { 'name' => 'answered_earlier' } },
          { 'message_type' => 'agent', 'content' => 'Working on it' },
          issue_request,
          mr_request
        ]
      end

      it 'collects only the trailing run, in log order' do
        expect(pending.calls.pluck(:name)).to eq(%w[create_issue create_merge_request])
      end
    end

    context 'when the log has no trailing approval request' do
      let(:ui_chat_log) do
        [
          issue_request,
          { 'message_type' => 'agent', 'content' => 'Done' }
        ]
      end

      it { is_expected.to be_nil }
    end

    context 'when a request entry carries no tool_info (plan approval)' do
      let(:ui_chat_log) do
        [{ 'message_type' => 'request', 'content' => 'Approve the plan to continue', 'tool_info' => nil }]
      end

      it { is_expected.to be_nil }
    end

    context 'when a request in the trailing run carries no message_id' do
      let(:ui_chat_log) { [issue_request, mr_request.except('message_id')] }

      it 'fails closed instead of fingerprinting on tool name and args' do
        is_expected.to be_nil
      end
    end
  end

  describe '#tool_names' do
    it 'lists the tool of every pending call, in log order' do
      expect(described_class.new([issue_request, mr_request]).tool_names)
        .to eq(%w[create_issue create_merge_request])
    end
  end

  describe '#fingerprint' do
    subject(:fingerprint) { described_class.new([issue_request, mr_request]).fingerprint }

    it 'is a stable hex digest of every pending tool call' do
      expect(fingerprint).to match(/\A\h{16}\z/)
      expect(fingerprint).to eq(described_class.new([issue_request.deep_dup, mr_request.deep_dup]).fingerprint)
    end

    it 'differs from the fingerprint of a subset' do
      expect(fingerprint).not_to eq(described_class.new([issue_request]).fingerprint)
    end

    it 'changes with the order of the calls' do
      expect(fingerprint).not_to eq(described_class.new([mr_request, issue_request]).fingerprint)
    end

    it 'tells apart two pauses asking for the same tool with the same args' do
      replay = described_class.new([issue_request.merge('message_id' => 'toolu_02issue'), mr_request])

      expect(fingerprint).not_to eq(replay.fingerprint)
    end

    it 'ignores content and args changes when the message_id is unchanged' do
      reworded = described_class.new([
        issue_request.merge('content' => 'Reworded'),
        mr_request.deep_merge('tool_info' => { 'args' => { 'title' => 'Other' } })
      ])

      expect(fingerprint).to eq(reworded.fingerprint)
    end
  end
end
