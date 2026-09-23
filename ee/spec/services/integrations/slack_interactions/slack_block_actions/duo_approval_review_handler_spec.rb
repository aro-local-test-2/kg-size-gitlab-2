# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackInteractions::SlackBlockActions::DuoApprovalReviewHandler, feature_category: :duo_agent_platform do
  describe '#execute' do
    let_it_be(:chat_name) { create(:chat_name) }
    let_it_be(:slack_installation) { create(:slack_integration, team_id: chat_name.team_id) }
    let_it_be(:owner) { chat_name.user }

    let(:workflow) { create(:duo_workflows_workflow, :tool_call_approval_required, user: owner) }

    let(:request_entry) do
      {
        'message_type' => 'request',
        'message_id' => 'toolu_01issue',
        'content' => 'Tool create_issue requires approval',
        'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report' } }
      }
    end

    let(:fingerprint) { Ai::DuoWorkflows::PendingToolApproval.new(request_entry).fingerprint }
    let(:action_value) { "#{workflow.id}:#{fingerprint}" }
    let(:action) { { action_id: 'duo_approval_review', value: action_value } }
    let(:params) do
      {
        team: { id: chat_name.team_id },
        user: { id: chat_name.chat_id },
        trigger_id: 'trigger-123',
        actions: [action]
      }
    end

    let(:opened_views) { [] }

    subject(:execute) { described_class.new(params, action).execute }

    before do
      allow_next_found_instance_of(Ai::DuoWorkflows::Workflow) do |instance|
        allow(instance).to receive(:latest_ui_chat_log).and_return([request_entry])
      end

      allow_next_instance_of(::Slack::API) do |api|
        allow(api).to receive(:open_view) { |**kwargs| opened_views << kwargs }
      end
    end

    it 'opens the approval modal for the session owner', :aggregate_failures do
      execute

      view = opened_views.sole
      expect(view[:trigger_id]).to eq('trigger-123')
      expect(view[:view]).to include(
        callback_id: Integrations::SlackInteractions::DuoToolApprovalModal::CALLBACK_ID,
        private_metadata: action_value
      )
    end

    it 'has no side effects on the session' do
      expect { execute }.not_to change { workflow.reload.attributes }
    end

    context 'when the clicker is not the session owner' do
      let_it_be(:other_chat_name) { create(:chat_name, team_id: chat_name.team_id) }

      let(:params) { super().merge(user: { id: other_chat_name.chat_id }) }

      it 'opens the not-owner notice without the tool arguments', :aggregate_failures do
        execute

        view = opened_views.sole[:view]
        expect(view).to eq(Integrations::SlackInteractions::DuoToolApprovalModal.not_owner_view)
        expect(view.to_json).to exclude('Bug report')
      end
    end

    context 'when the Slack account is not linked to a GitLab user' do
      let(:params) { super().merge(user: { id: 'U_UNKNOWN' }) }

      it 'opens the account-not-linked notice' do
        execute

        expect(opened_views.sole[:view])
          .to eq(Integrations::SlackInteractions::DuoToolApprovalModal.account_not_linked_view)
      end
    end

    context 'when the fingerprint no longer matches the pending request' do
      let(:action_value) { "#{workflow.id}:aaaabbbbccccdddd" }

      it 'opens the stale notice' do
        execute

        expect(opened_views.sole[:view]).to eq(Integrations::SlackInteractions::DuoToolApprovalModal.stale_view)
      end
    end

    context 'when the session is no longer waiting for a tool approval' do
      let(:workflow) { create(:duo_workflows_workflow, :running, user: owner) }

      it 'opens the stale notice' do
        execute

        expect(opened_views.sole[:view]).to eq(Integrations::SlackInteractions::DuoToolApprovalModal.stale_view)
      end
    end

    context 'when the slack_duo_api_flow flag is disabled' do
      before do
        stub_feature_flags(slack_duo_api_flow: false)
      end

      it 'does nothing' do
        execute

        expect(opened_views).to be_empty
      end
    end

    context 'when the session has no resource parent' do
      before do
        allow_next_found_instance_of(Ai::DuoWorkflows::Workflow) do |instance|
          allow(instance).to receive_messages(latest_ui_chat_log: [request_entry], resource_parent: nil)
        end
      end

      it 'evaluates the flag without an actor and still opens the modal' do
        execute

        expect(opened_views.sole[:view]).to include(
          callback_id: Integrations::SlackInteractions::DuoToolApprovalModal::CALLBACK_ID
        )
      end
    end

    context 'when the Slack workspace has no bot installation' do
      let(:params) { super().merge(team: { id: 'T_NO_INSTALL' }) }

      it 'does nothing' do
        execute

        expect(opened_views).to be_empty
      end
    end

    context 'when the workflow does not exist' do
      let(:action_value) { "#{non_existing_record_id}:#{fingerprint}" }

      it 'does nothing' do
        execute

        expect(opened_views).to be_empty
      end
    end

    context 'when the value is malformed' do
      let(:action_value) { 'not-a-valid-value' }

      it 'does nothing' do
        execute

        expect(opened_views).to be_empty
      end
    end

    context 'when there is no trigger_id' do
      let(:params) { super().except(:trigger_id) }

      it 'does nothing' do
        execute

        expect(opened_views).to be_empty
      end
    end
  end
end
