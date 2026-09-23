# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::GetDuoSessionTool, feature_category: :mcp_server do
  let_it_be(:ai_settings, freeze: false) { create(:namespace_ai_settings, duo_workflow_mcp_enabled: true) }
  let_it_be(:group, freeze: false) { create(:group, ai_settings: ai_settings) }
  let_it_be(:user, freeze: false) { create(:user, developer_of: group) }
  let_it_be(:other_user, freeze: false) { create(:user, developer_of: group) }
  let_it_be(:project, freeze: false) { create(:project, group: group) }

  let(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }
  let(:params) { { workflow_id: workflow.id } }
  let(:tool) { described_class.new(current_user: user, params: params) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(any_args).and_return(true)
    # rubocop:disable RSpec/AnyInstanceOf -- Duo Agent Platform authorization is evaluated by the workflow policy.
    allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
    # rubocop:enable RSpec/AnyInstanceOf
  end

  describe '#build_variables' do
    it 'converts the numeric workflow ID to the GraphQL global ID' do
      expect(tool.build_variables).to eq(
        workflowId: Gitlab::GlobalId.build(model_name: ::Ai::DuoWorkflows::Workflow.name, id: workflow.id).to_s
      )
    end
  end

  describe '#execute' do
    it 'returns compact progress and a polling hint for a running session' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [{ content: 'Working on the request', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'running',
          'web_url' => workflow.web_url,
          'poll_after_seconds' => 30
        }
      )
      expect(result[:content]).to eq([
        {
          type: 'text',
          text: "Status: running. Poll again in 30 seconds.\n\nLatest agent update: Working on the request"
        }
      ])
    end

    it 'returns the running fallback when the checkpoint contains no agent messages' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [{ content: 'Please continue.', role: 'user', message_type: 'user' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'running',
          'web_url' => workflow.web_url,
          'poll_after_seconds' => 30
        },
        content: [{ type: 'text', text: 'Status: running. Poll again in 30 seconds.' }]
      )
    end

    it 'falls back to the earlier agent message when the latest agent message is blank' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [
        { content: 'Working on the request', role: 'assistant', message_type: 'agent' },
        { content: '', role: 'assistant', message_type: 'agent' }
      ])

      result = tool.execute

      expect(result[:content]).to eq([
        {
          type: 'text',
          text: "Status: running. Poll again in 30 seconds.\n\nLatest agent update: Working on the request"
        }
      ])
    end

    it 'returns the final answer when a finished session ends with an empty agent turn' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [
        { content: 'Here is the full answer.', role: 'assistant', message_type: 'agent' },
        { content: '', role: 'assistant', message_type: 'agent' }
      ])

      result = tool.execute

      expect(result).to include(
        isError: false,
        content: [{ type: 'text', text: 'Here is the full answer.' }]
      )
    end

    it 'returns the final answer when a finished session ends with a tool-only turn' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [
        { content: 'Here is the full answer.', role: 'assistant', message_type: 'agent' },
        { content: 'read_file', message_type: 'tool' }
      ])

      result = tool.execute

      expect(result).to include(
        isError: false,
        content: [{ type: 'text', text: 'Here is the full answer.' }]
      )
    end

    it 'returns the latest agent answer for a finished session when the latest message is not from the agent' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [
        { content: 'The change is complete.', role: 'assistant', message_type: 'agent' },
        { content: 'Thanks', role: 'user', message_type: 'user' }
      ])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'finished',
          'web_url' => workflow.web_url
        },
        content: [{ type: 'text', text: 'The change is complete.' }]
      )
    end

    context 'with a flow-shaped chat log' do
      # Flow sessions tag the agent with message_type 'agent' and carry no role.
      it 'returns the final answer for a finished session' do
        workflow.update!(status: status_value(:finished))
        add_checkpoint(workflow, [
          { content: 'Ran the migration.', message_type: 'agent' },
          { content: 'read_file', message_type: 'tool' }
        ])

        result = tool.execute

        expect(result).to include(
          isError: false,
          content: [{ type: 'text', text: 'Ran the migration.' }]
        )
      end

      it 'returns compact progress for a running session' do
        workflow.update!(status: status_value(:running))
        add_checkpoint(workflow, [{ content: 'Working on the request', message_type: 'agent' }])

        result = tool.execute

        expect(result[:content]).to eq([
          {
            type: 'text',
            text: "Status: running. Poll again in 30 seconds.\n\nLatest agent update: Working on the request"
          }
        ])
      end

      it 'returns the finished fallback when no agent message is present' do
        workflow.update!(status: status_value(:finished))
        add_checkpoint(workflow, [
          { content: 'Run the migration', message_type: 'user' },
          { content: 'read_file', message_type: 'tool' }
        ])

        result = tool.execute

        expect(result).to include(
          isError: false,
          content: [{ type: 'text', text: 'Session finished, but no final answer was produced.' }]
        )
      end
    end

    it 'identifies input required as a completed chat turn' do
      workflow.update!(status: status_value(:input_required))
      add_checkpoint(workflow, [{ content: 'How should I proceed?', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'input required',
          'turn_complete' => true,
          'web_url' => workflow.web_url
        },
        content: [{ type: 'text', text: 'How should I proceed?' }]
      )
    end

    it 'explains how to resume a session awaiting tool-call approval' do
      workflow.update!(status: status_value(:tool_call_approval_required))
      add_checkpoint(workflow, [{ content: 'I need approval.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'tool call approval required',
          'awaiting_approval' => true,
          'web_url' => workflow.web_url
        }
      )
      expect(result.dig(:content, 0, :text)).to include(
        'I need approval.',
        'Polling will NOT move it forward.',
        "send_duo_session_input with workflow_id=#{workflow.id}",
        'human_approval=true to approve, or false to reject'
      )
    end

    it 'explains how to resume a session awaiting plan approval' do
      workflow.update!(status: status_value(:plan_approval_required))
      add_checkpoint(workflow, [{ content: 'Here is my plan.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'plan approval required',
          'awaiting_approval' => true,
          'web_url' => workflow.web_url
        }
      )
      expect(result.dig(:content, 0, :text)).to include(
        'Here is my plan.',
        'Polling will NOT move it forward.',
        "send_duo_session_input with workflow_id=#{workflow.id}"
      )
    end

    it 'tells the agent that polling will not move a paused session forward' do
      workflow.update!(status: status_value(:paused))
      add_checkpoint(workflow, [{ content: 'Pausing here.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'paused',
          'paused' => true,
          'web_url' => workflow.web_url
        }
      )
      expect(result.dig(:content, 0, :text)).to include(
        'Pausing here.',
        'Polling will NOT move it forward',
        "See #{workflow.web_url} to resume it."
      )
      expect(result[:structuredContent]).not_to include('poll_after_seconds')
    end

    it 'returns a polling hint for a session that has not started yet' do
      workflow.update!(status: status_value(:created))

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'created',
          'web_url' => workflow.web_url,
          'poll_after_seconds' => 30
        },
        content: [{ type: 'text', text: 'Status: created. Poll again in 30 seconds.' }]
      )
    end

    it 'returns a session URL for a stopped session' do
      workflow.update!(status: status_value(:stopped))

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'stopped',
          'web_url' => workflow.web_url
        },
        content: [{ type: 'text', text: "Session stopped. See #{workflow.web_url} for details." }]
      )
    end

    it 'returns a session URL for terminal statuses without a final answer' do
      workflow.update!(status: status_value(:failed))

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: {
          'workflow_id' => workflow.id,
          'status' => 'failed',
          'web_url' => workflow.web_url
        },
        content: [{ type: 'text', text: "Session failed. See #{workflow.web_url} for details." }]
      )
    end

    it 'returns the GraphQL not-found error for an unknown workflow' do
      result = described_class.new(current_user: user, params: { workflow_id: non_existing_record_id }).execute

      expect(result).to include(isError: true)
      expect(result.dig(:content, 0, :text)).to include('Workflow not found')
    end

    # The resolver answers not-found rather than forbidden so the response cannot
    # be used to probe which workflow IDs exist.
    it 'hides a workflow owned by another user behind the not-found error' do
      other_workflow = create(:duo_workflows_workflow, user: other_user, project: project)

      result = described_class.new(current_user: user, params: { workflow_id: other_workflow.id }).execute

      expect(result).to include(isError: true)
      expect(result.dig(:content, 0, :text)).to include('Workflow not found')
    end
  end

  private

  def add_checkpoint(workflow, messages)
    create(:duo_workflows_checkpoint, workflow: workflow, project: project,
      checkpoint: { channel_values: { ui_chat_log: messages } })
  end

  def status_value(status)
    ::Ai::DuoWorkflows::Workflow.state_machines[:status].states.fetch(status).value
  end
end
