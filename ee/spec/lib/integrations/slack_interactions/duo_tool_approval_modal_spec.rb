# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackInteractions::DuoToolApprovalModal, feature_category: :duo_agent_platform do
  let(:issue_request) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01issue',
      'content' => 'Tool create_issue requires approval',
      'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report', 'force' => true } }
    }
  end

  let(:mr_request) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01mr',
      'content' => nil,
      'tool_info' => { 'name' => 'create_merge_request', 'args' => {} }
    }
  end

  let(:requests) { [issue_request, mr_request] }
  let(:pending) { Ai::DuoWorkflows::PendingToolApproval.new(requests) }

  describe '#build' do
    subject(:payload) { described_class.new(123, pending).build }

    def sections
      payload[:blocks].select { |block| block[:type] == 'section' }.map { |block| block.dig(:text, :text) }
    end

    it 'builds a modal that carries the workflow and fingerprint in private_metadata', :aggregate_failures do
      expect(payload).to include(
        type: 'modal',
        callback_id: described_class::CALLBACK_ID,
        private_metadata: "123:#{pending.fingerprint}"
      )
      expect(payload[:submit][:text]).to eq(s_('DuoSlack|Submit'))
      expect(payload[:close][:text]).to eq(s_('DuoSlack|Cancel'))
    end

    it 'introduces the batch with a pluralized count' do
      expect(sections.first).to eq(
        'GitLab Duo wants to run 2 actions. Review them and choose whether to continue.'
      )
    end

    it 'renders each call with its arguments as a code block, falling back to the tool name', :aggregate_failures do
      expect(sections[1]).to eq(
        "Tool create_issue requires approval\n```\n{\n  \"title\": \"Bug report\",\n  \"force\": true\n}\n```"
      )
      expect(sections[2]).to eq('GitLab Duo wants to run the create_merge_request tool.')
    end

    it 'collects one approve/deny decision for the whole batch', :aggregate_failures do
      decision = payload[:blocks].last

      expect(decision).to include(type: 'input', block_id: described_class::DECISION_BLOCK_ID)
      expect(decision[:element]).to include(type: 'radio_buttons', action_id: described_class::DECISION_ACTION_ID)
      expect(decision[:element][:options].pluck(:value)).to eq(%w[approve deny])
    end

    it 'stays within the Slack modal limits', :aggregate_failures do
      expect(payload[:title][:text].length).to be <= 24
      expect(payload[:blocks].size).to be <= 100
      expect(sections).to all(have_attributes(length: (..3000)))
    end

    context 'when a single call is pending' do
      let(:requests) { [issue_request] }

      it 'uses the singular intro' do
        expect(sections.first).to eq(
          'GitLab Duo wants to run 1 action. Review it and choose whether to continue.'
        )
      end
    end

    context 'when one argument value is oversized' do
      let(:issue_request) do
        super().deep_merge('tool_info' => { 'args' => { 'title' => 'x' * 5000, 'force' => true } })
      end

      it 'truncates that value but keeps every other key visible', :aggregate_failures do
        text = sections[1]

        expect(text).to include('"force": true')
        expect(text).to include('...')
        expect(text.length).to be <= 3000
      end
    end

    context 'when the request text is oversized' do
      let(:issue_request) { super().merge('content' => 'word ' * 400) }

      it 'truncates the text and keeps the arguments readable', :aggregate_failures do
        text = sections[1]

        expect(text.length).to be <= 3000
        expect(text).to include('...')
        expect(text).to include('"force": true')
      end

      context 'and the tool takes no arguments' do
        let(:issue_request) { super().merge('tool_info' => { 'name' => 'create_issue', 'args' => {} }) }

        it 'still stays within the section limit' do
          expect(sections[1].length).to be <= described_class::SUMMARY_MAX_LENGTH
        end
      end
    end

    context 'when a call has so many arguments that the section would overflow' do
      let(:issue_request) do
        args = (1..20).to_h { |i| ["key_#{i}", 'y' * 300] }
        super().deep_merge('tool_info' => { 'args' => args })
      end

      it 'truncates the code block at a line boundary and marks the cut', :aggregate_failures do
        text = sections[1]

        expect(text.length).to be <= 3000
        expect(text).to end_with("\n…\n```")
      end
    end

    context 'when more calls are pending than the modal can show' do
      let(:requests) do
        (1..(described_class::MAX_CALLS + 3)).map { |i| issue_request.merge('message_id' => "toolu_#{i}") }
      end

      it 'caps the rendered calls and says how many are hidden', :aggregate_failures do
        expect(payload[:blocks].size).to be <= 100
        expect(payload[:blocks].count { |block| block[:type] == 'divider' }).to eq(described_class::MAX_CALLS)
        expect(payload[:blocks][-2]).to include(type: 'context')
        expect(payload[:blocks][-2][:elements].sole[:text]).to eq('3 more actions are not shown here.')
      end
    end
  end

  describe 'notice views' do
    using RSpec::Parameterized::TableSyntax

    where(:view, :text) do
      :not_owner_view          | 'Only the person who started this session can respond to this request.'
      :stale_view              | 'This approval request has already been answered.'
      :account_not_linked_view | 'Your Slack account is not connected to a GitLab account, ' \
        'so you cannot respond to this request.'
    end

    with_them do
      subject(:payload) { described_class.public_send(view) }

      it 'is a close-only modal carrying the notice', :aggregate_failures do
        expect(payload).to include(type: 'modal')
        expect(payload).not_to include(:submit, :callback_id)
        expect(payload[:blocks].sole.dig(:text, :text)).to eq(text)
      end
    end
  end
end
