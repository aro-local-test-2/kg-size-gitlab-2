# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackEvents::AppMentionedService, feature_category: :duo_agent_platform do
  describe '#execute' do
    let_it_be(:slack_installation) { create(:slack_integration) }
    let_it_be(:user) { create(:user) }
    let_it_be(:chat_name) do
      create(:chat_name, user: user, team_id: slack_installation.team_id, chat_id: 'U0123ABCDEF')
    end

    let_it_be(:project) { create(:project) }
    let_it_be(:service_account) { create(:user, :service_account) }

    let(:slack_workspace_id) { slack_installation.team_id }
    let(:slack_user_id) { chat_name.chat_id }
    let(:channel_id) { 'C0123ABCDEF' }
    let(:message_ts) { '1234567890.123456' }
    let(:event_text) { "<@#{slack_installation.bot_user_id}> hello world" }

    let(:params) do
      {
        team_id: slack_workspace_id,
        event: {
          user: slack_user_id,
          channel: channel_id,
          ts: message_ts,
          text: event_text
        }
      }
    end

    let(:message_permalink) { 'https://myworkspace.slack.com/archives/C0123ABCDEF/p1234567890123456' }

    let(:trigger_result) do
      mock_workflow = instance_double(Ai::DuoWorkflows::Workflow, id: 1)
      ServiceResponse.success(payload: { workflow: mock_workflow })
    end

    let(:mock_adapter) do
      instance_double(
        Ai::Messaging::Adapters::Slack,
        trigger: trigger_result,
        build_callback_context: { 'team_id' => slack_workspace_id, 'channel_id' => channel_id,
                                  'thread_ts' => message_ts, 'message_ts' => message_ts,
                                  'user_id' => slack_user_id },
        deliver_error: nil
      )
    end

    let(:resolver_result) do
      ServiceResponse.success(payload: {
        project: project,
        service_account: service_account,
        flow_config_id: 'developer',
        flow_config_schema_version: 'v1',
        flow_version: nil
      })
    end

    let(:thread_replies_response) do
      {
        ok: true,
        messages: [
          { user: slack_user_id, text: event_text, ts: message_ts },
          { user: 'U_OTHER', text: 'a reply', ts: '1234567891.000001' }
        ]
      }
    end

    let(:slack_goal_max) { EE::Integrations::SlackEvents::AppMentionedService::SLACK_GOAL_MAX }

    subject(:execute) { described_class.new(params).execute }

    def slack_api_url(method)
      "#{Slack::API::BASE_URL}/#{method}"
    end

    before do
      stub_feature_flags(slack_duo_agent: user)
      stub_application_setting(instance_level_ai_beta_features_enabled: true)
      allow_next_instance_of(ChatNames::FindUserService) do |service|
        allow(service).to receive(:execute).and_return(chat_name)
      end
      allow(user).to receive(:allowed_to_use?).with(:duo_agent_platform).and_return(true)

      stub_request(:post, slack_api_url('reactions.add')).to_return(status: 200, body: { ok: true }.to_json,
        headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, slack_api_url('reactions.remove')).to_return(status: 200, body: { ok: true }.to_json,
        headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, slack_api_url('chat.postMessage')).to_return(status: 200, body: { ok: true }.to_json,
        headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, slack_api_url('chat.postEphemeral')).to_return(status: 200, body: { ok: true }.to_json,
        headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, slack_api_url('conversations.replies')).with(query: hash_including({}))
        .to_return(status: 200, body: thread_replies_response.to_json,
          headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, slack_api_url('chat.getPermalink')).with(query: hash_including({}))
        .to_return(status: 200, body: { ok: true, permalink: message_permalink }.to_json,
          headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, slack_api_url('conversations.history')).with(query: hash_including({}))
        .to_return(status: 200, body: { ok: true, messages: [] }.to_json,
          headers: { 'Content-Type' => 'application/json' })

      # Stub the resolver and adapter trigger
      namespace_result = ServiceResponse.success(payload: {
        container: project.namespace,
        flow_config_id: 'slack_assistant',
        flow_config_schema_version: 'v1',
        flow_version: '^1.0.0'
      })
      allow_next_instance_of(Ai::Messaging::DefaultProjectFlowResolver) do |resolver|
        allow(resolver).to receive_messages(execute: resolver_result, resolve_namespace: namespace_result)
      end
      allow(Ai::Messaging::Adapters::Slack).to receive(:new).and_return(mock_adapter)

      stub_feature_flags(slack_duo_api_flow: false)
    end

    describe 'experiment and beta Duo features setting' do
      context 'when the setting is turned off' do
        before do
          stub_application_setting(instance_level_ai_beta_features_enabled: false)
        end

        it 'does not trigger a flow and posts the ephemeral message' do
          expect(mock_adapter).not_to receive(:trigger)

          is_expected.to be_success

          expect(WebMock).to have_requested(:post, slack_api_url('chat.postEphemeral')).with(
            body: hash_including(
              'text' => a_string_including(
                'This feature requires experiment and beta GitLab Duo features to be turned on.'
              )
            )
          )
        end
      end

      context 'when the setting is turned on' do
        it 'triggers the flow' do
          expect(mock_adapter).to receive(:trigger).and_return(trigger_result)

          is_expected.to be_success
        end
      end
    end

    it 'triggers a Duo flow via the Slack adapter' do
      expect(mock_adapter).to receive(:trigger).with(
        an_instance_of(Ai::Messaging::Adapters::Base::TriggerBundle)
      ).and_return(trigger_result)

      is_expected.to be_success
    end

    it 'tracks the triggered flow' do
      expect { execute }.to trigger_internal_events('trigger_slack_duo').with(
        user: user, project: project, namespace: project.namespace
      )
    end

    it 'builds the TriggerBundle with correct params', :aggregate_failures do
      expect(mock_adapter).to receive(:trigger) do |bundle|
        expect(bundle.current_user).to eq(user)
        expect(bundle.service_account).to eq(service_account)
        expect(bundle.flow_reference).to eq('developer/v1')
        expect(bundle.project).to eq(project)
        expect(bundle.goal).to include('<conversation>')
        expect(bundle.goal).to include('standard Markdown')
        expect(bundle.goal).to include('Always write links as [text](url)')
        expect(bundle.source_type).to eq(:slack)
        expect(bundle.source_link).to eq(message_permalink)
        trigger_result
      end

      execute
    end

    it 'sets source_link to the permalink fetched from chat.getPermalink' do
      expect(mock_adapter).to receive(:trigger) do |bundle|
        expect(bundle.source_link).to eq(message_permalink)
        trigger_result
      end

      execute

      expect(WebMock).to have_requested(:get, slack_api_url('chat.getPermalink')).with(
        query: { channel: channel_id, message_ts: message_ts }
      )
    end

    context 'when fetching the permalink fails' do
      before do
        stub_request(:get, slack_api_url('chat.getPermalink')).with(query: hash_including({}))
          .to_return(status: 200, body: { ok: false, error: 'message_not_found' }.to_json,
            headers: { 'Content-Type' => 'application/json' })
      end

      it 'still triggers the flow with a nil source_link' do
        expect(mock_adapter).to receive(:trigger) do |bundle|
          expect(bundle.source_link).to be_nil
          trigger_result
        end

        execute
      end
    end

    it 'passes the correct flow_reference to the resolver' do
      expect(Ai::Messaging::DefaultProjectFlowResolver).to receive(:new).with(
        flow_reference: 'developer/v1',
        current_user: user
      ).and_call_original

      execute
    end

    context 'when slack_duo_api_flow is enabled' do
      before do
        stub_feature_flags(slack_duo_api_flow: true)
      end

      it 'passes the API flow reference to the resolver' do
        expect(Ai::Messaging::DefaultProjectFlowResolver).to receive(:new).with(
          flow_reference: 'slack_assistant/v1',
          current_user: user
        ).and_call_original

        execute
      end

      it 'builds the TriggerBundle with the API flow reference' do
        expect(mock_adapter).to receive(:trigger) do |bundle|
          expect(bundle.flow_reference).to eq('slack_assistant/v1')
          trigger_result
        end

        execute
      end

      it 'sends the conversation with no preamble', :aggregate_failures do
        expect(mock_adapter).to receive(:trigger) do |bundle|
          expect(bundle.goal).to start_with('<')
          expect(bundle.goal).not_to include('You were mentioned')
          trigger_result
        end

        execute
      end
    end

    describe 'resolver failure errors' do
      using RSpec::Parameterized::TableSyntax

      where(:reason, :expected_error) do
        :namespace_not_configured | :namespace_not_configured
        :flow_not_enabled         | :flow_not_enabled
        :workspace_project_error  | :workspace_project_error
        :service_account_error    | :service_account_error
        nil                       | nil
      end

      with_them do
        let(:resolver_result) do
          ServiceResponse.error(message: 'resolver failed', reason: reason)
        end

        it 'calls deliver_error on the adapter with the resolver reason' do
          expect(mock_adapter).to receive(:deliver_error).with(
            callback_context: anything,
            error: expected_error
          )

          execute
        end

        it 'tracks the blocked mention with the resolver reason' do
          expect { execute }.to trigger_internal_events('block_slack_duo_mention').with(
            user: user, additional_properties: { property: "flow_resolver_#{reason || 'failed'}" }
          )
        end
      end
    end

    context 'when adapter.trigger fails' do
      let(:trigger_result) do
        ServiceResponse.error(message: 'workflow creation failed', reason: :execute_workflow_failed)
      end

      it 'logs the failure and still returns success' do
        expect(Gitlab::IntegrationsLogger).to receive(:info).with(
          hash_including(
            message: 'Duo Messaging: flow trigger failed',
            failure_reason: :execute_workflow_failed
          )
        )

        is_expected.to be_success
      end

      it 'does not track a triggered flow' do
        expect { execute }.to not_trigger_internal_events('trigger_slack_duo')
      end

      it 'tracks the blocked mention with the trigger failure reason' do
        expect { execute }.to trigger_internal_events('block_slack_duo_mention').with(
          user: user, additional_properties: { property: 'flow_trigger_failed' }
        )
      end
    end

    context 'when message is a root mention (single message, no existing thread)' do
      it 'fetches thread context to build the goal' do
        is_expected.to be_success

        expect(WebMock).to have_requested(:get, slack_api_url('conversations.replies')).with(
          query: hash_including('channel' => channel_id, 'ts' => message_ts)
        )
      end
    end

    context 'when message is in an existing thread' do
      let(:thread_ts) { '1111111111.000001' }
      let(:params) do
        {
          team_id: slack_workspace_id,
          event: {
            user: slack_user_id,
            channel: channel_id,
            ts: message_ts,
            thread_ts: thread_ts,
            text: event_text
          }
        }
      end

      it 'fetches replies using thread_ts' do
        is_expected.to be_success

        expect(WebMock).to have_requested(:get, slack_api_url('conversations.replies')).with(
          query: hash_including('channel' => channel_id, 'ts' => thread_ts)
        )
      end

      it 'anchors channel history to the thread root, not the mention itself' do
        is_expected.to be_success

        expect(WebMock).to have_requested(:get, slack_api_url('conversations.history'))
          .with(query: hash_including('latest' => thread_ts))
      end
    end

    context 'when conversations.replies returns an error' do
      before do
        stub_request(:get, slack_api_url('conversations.replies')).with(query: hash_including({}))
          .to_return(status: 200, body: { ok: false, error: 'channel_not_found' }.to_json,
            headers: { 'Content-Type' => 'application/json' })
      end

      it 'logs the error and falls back gracefully' do
        expect(Gitlab::IntegrationsLogger).to receive(:error).with(
          hash_including(message: 'Slack API error when fetching thread')
        )

        is_expected.to be_success
      end
    end

    context 'when conversations.replies raises an HTTP error' do
      before do
        stub_request(:get, slack_api_url('conversations.replies')).with(query: hash_including({}))
          .to_raise(Errno::ECONNREFUSED.new('error'))
      end

      it 'tracks the exception and falls back gracefully' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(Errno::ECONNREFUSED), slack_workspace_id: slack_workspace_id)

        is_expected.to be_success
      end
    end

    context 'when build_user_map raises an unexpected error' do
      before do
        allow(ChatName).to receive(:for_team_and_chat_ids).and_raise(ActiveRecord::StatementInvalid, 'db error')
      end

      it 'tracks the exception and still succeeds' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(ActiveRecord::StatementInvalid), slack_workspace_id: slack_workspace_id)

        is_expected.to be_success
      end
    end

    describe 'author resolution priority' do
      let(:author_limit) { 3 }

      let(:channel_history_response) do
        {
          ok: true,
          messages: [{ user: 'U_CHANNEL_AUTHOR', text: 'channel background', ts: '1234567700.000001' }]
        }
      end

      before do
        stub_const(
          'EE::Integrations::SlackEvents::AppMentionedService::USER_MAP_AUTHOR_LIMIT', author_limit
        )

        %w[U_NEWEST_THREAD U_MIDDLE_THREAD U_OLDEST_THREAD U_CHANNEL_AUTHOR].each do |chat_id|
          create(:chat_name, team_id: slack_installation.team_id, chat_id: chat_id)
        end

        stub_request(:get, slack_api_url('conversations.history')).with(query: hash_including({}))
          .to_return(status: 200, body: channel_history_response.to_json,
            headers: { 'Content-Type' => 'application/json' })
      end

      def captured_goal
        goal = nil

        expect(mock_adapter).to receive(:trigger) do |bundle|
          goal = bundle.goal
          trigger_result
        end

        execute
        goal
      end

      context 'when the conversation fits within the cap' do
        let(:thread_replies_response) do
          {
            ok: true,
            messages: [
              { user: 'U_OLDEST_THREAD', text: 'the thread root', ts: '1234567800.000001' },
              { user: slack_user_id, text: event_text, ts: message_ts }
            ]
          }
        end

        it 'annotates thread and channel authors alike', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include('<message author="U_OLDEST_THREAD" gitlab=')
          expect(goal).to include('<message author="U_CHANNEL_AUTHOR" gitlab=')
        end
      end

      context 'when the thread alone exceeds the cap' do
        let(:thread_replies_response) do
          {
            ok: true,
            messages: [
              { user: 'U_OLDEST_THREAD', text: 'the thread root', ts: '1234567800.000001' },
              { user: 'U_MIDDLE_THREAD', text: 'a middle reply', ts: '1234567850.000001' },
              { user: 'U_NEWEST_THREAD', text: 'a recent reply', ts: '1234567899.000001' },
              { user: slack_user_id, text: event_text, ts: message_ts }
            ]
          }
        end

        it 'annotates the newest authors and leaves the oldest bare', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include("<message author=\"#{slack_user_id}\" gitlab=\"@#{user.username}\">")
          expect(goal).to include('<message author="U_NEWEST_THREAD" gitlab=')
          expect(goal).to include('<message author="U_MIDDLE_THREAD" gitlab=')
          expect(goal).to include('<message author="U_OLDEST_THREAD">')
          expect(goal).to include('<message author="U_CHANNEL_AUTHOR">')
        end
      end
    end

    context 'when thread has multiple messages with linked and unlinked users' do
      let(:other_chat_name) { create(:chat_name, team_id: slack_installation.team_id, chat_id: 'U999OTHER') }
      let(:unlinked_user_id) { 'U_UNKNOWN' }
      let(:thread_replies_response) do
        {
          ok: true,
          messages: [
            { user: slack_user_id, text: 'Can someone help?', ts: '1234567890.000001' },
            { user: other_chat_name.chat_id, text: 'Sure!', ts: '1234567891.000001' },
            { user: unlinked_user_id, text: 'Me too', ts: '1234567892.000001' },
            { user: slack_user_id, text: event_text, ts: message_ts }
          ]
        }
      end

      it 'annotates each message with its author, linked or not', :aggregate_failures do
        captured_goal = nil

        expect(mock_adapter).to receive(:trigger) do |bundle|
          captured_goal = bundle.goal
          trigger_result
        end

        execute

        expect(captured_goal).to exclude('<participants>')
        expect(captured_goal).to include('<conversation>')
        expect(captured_goal).to include("<message author=\"#{slack_user_id}\" gitlab=\"@#{user.username}\">")
        expect(captured_goal)
          .to include("<message author=\"#{other_chat_name.chat_id}\" gitlab=\"@#{other_chat_name.user.username}\">")
        expect(captured_goal).to include('Can someone help?')
        expect(captured_goal).to include("<message author=\"#{unlinked_user_id}\">")
        expect(captured_goal).to exclude("<message author=\"#{unlinked_user_id}\" gitlab=")
        expect(captured_goal).to include('standard Markdown')
      end
    end

    describe 'channel context' do
      let(:channel_history_response) do
        {
          ok: true,
          messages: [
            { user: 'U_CHANNEL', text: 'newest channel message', ts: '1234567880.000002' },
            { user: 'U_CHANNEL', text: 'older channel message', ts: '1234567880.000001' }
          ]
        }
      end

      before do
        stub_request(:get, slack_api_url('conversations.history')).with(query: hash_including({}))
          .to_return(status: 200, body: channel_history_response.to_json,
            headers: { 'Content-Type' => 'application/json' })
      end

      def captured_goal
        goal = nil

        expect(mock_adapter).to receive(:trigger) do |bundle|
          goal = bundle.goal
          trigger_result
        end

        execute
        goal
      end

      it 'includes recent channel history oldest first', :aggregate_failures do
        goal = captured_goal

        expect(goal).to include('<channel_context>')
        expect(goal).to include('older channel message')
        expect(goal).to include('newest channel message')
        expect(goal.index('older channel message')).to be < goal.index('newest channel message')
      end

      it 'anchors the history to the mention, excluding anything newer' do
        captured_goal

        expect(WebMock).to have_requested(:get, slack_api_url('conversations.history'))
          .with(query: hash_including('latest' => message_ts))
      end

      context 'when the history contains channel events' do
        let(:channel_history_response) do
          {
            ok: true,
            messages: [
              { user: 'U_CHANNEL', text: 'a real message', ts: '1234567880.000004' },
              { user: 'U_JOINER', text: '<@U_JOINER> has joined the channel', subtype: 'channel_join',
                ts: '1234567880.000003' },
              { user: 'U_LEAVER', text: '<@U_LEAVER> has left the channel', subtype: 'channel_leave',
                ts: '1234567880.000002' },
              { user: 'U_CHANNEL', text: 'set the channel topic: standup', subtype: 'channel_topic',
                ts: '1234567880.000001' }
            ]
          }
        end

        it 'keeps conversational messages and drops the events', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include('a real message')
          expect(goal).to exclude('has joined the channel')
          expect(goal).to exclude('has left the channel')
          expect(goal).to exclude('set the channel topic')
        end
      end

      context 'when the history contains a bot message and a file share' do
        let(:channel_history_response) do
          {
            ok: true,
            messages: [
              { bot_id: 'B_CI', text: 'pipeline failed', subtype: 'bot_message', ts: '1234567880.000002' },
              { user: 'U_CHANNEL', text: 'here is the log', subtype: 'file_share', ts: '1234567880.000001' }
            ]
          }
        end

        it 'keeps them as conversation', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include('pipeline failed')
          expect(goal).to include('here is the log')
        end
      end

      context 'when a message carries its content outside text' do
        let(:channel_history_response) do
          {
            ok: true,
            messages: [
              { user: 'U_CHANNEL', text: 'a real message', ts: '1234567880.000003' },
              { user: 'U_CHANNEL', text: '', subtype: 'file_share', ts: '1234567880.000002',
                files: [{ name: 'trace.log' }] },
              { bot_id: 'B_CI', text: '', subtype: 'bot_message', ts: '1234567880.000001',
                blocks: [{ type: 'section' }] }
            ]
          }
        end

        it 'drops it rather than rendering an empty message', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include('a real message')
          expect(goal.scan('<message').length).to eq(3)
        end
      end

      it 'states the task first, then channel background, then the thread', :aggregate_failures do
        goal = captured_goal

        expect(goal.index('You were mentioned')).to be < goal.index('<channel_context>')
        expect(goal.index('</channel_context>')).to be < goal.index('<conversation>')
      end

      it 'over-fetches so the subtype filter has room to work' do
        captured_goal

        expect(WebMock).to have_requested(:get, slack_api_url('conversations.history')).with(
          query: hash_including(
            'channel' => channel_id,
            'limit' => EE::Integrations::SlackEvents::AppMentionedService::CHANNEL_CONTEXT_FETCH_LIMIT.to_s
          )
        )
      end

      context 'when channel events outnumber the render limit' do
        let(:render_limit) { 2 }

        let(:channel_history_response) do
          joins = Array.new(5) do |i|
            { user: "U_JOINER_#{i}", text: "<@U_JOINER_#{i}> has joined the channel", subtype: 'channel_join',
              ts: "12345678#{i}.000009" }
          end

          {
            ok: true,
            messages: [
              *joins,
              { user: 'U_CHANNEL', text: 'newest real message', ts: '1234567880.000003' },
              { user: 'U_CHANNEL', text: 'middle real message', ts: '1234567880.000002' },
              { user: 'U_CHANNEL', text: 'oldest real message', ts: '1234567880.000001' }
            ]
          }
        end

        before do
          stub_const(
            'EE::Integrations::SlackEvents::AppMentionedService::CHANNEL_CONTEXT_MESSAGE_LIMIT', render_limit
          )
        end

        it 'renders the newest conversational messages, not the events', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include('newest real message')
          expect(goal).to include('middle real message')
          expect(goal).to exclude('oldest real message')
          expect(goal).to exclude('has joined the channel')
        end
      end

      context 'when a channel author is not part of the thread' do
        let(:channel_chat_name) do
          create(:chat_name, team_id: slack_installation.team_id, chat_id: 'U_CHANNEL')
        end

        let(:channel_history_response) do
          {
            ok: true,
            messages: [{ user: channel_chat_name.chat_id, text: 'channel chatter', ts: '1234567880.000001' }]
          }
        end

        it 'annotates their channel message with their GitLab username' do
          expect(captured_goal).to include(
            %(<message author="#{channel_chat_name.chat_id}" gitlab="@#{channel_chat_name.user.username}">)
          )
        end
      end

      context 'when fetching channel history fails' do
        before do
          stub_request(:get, slack_api_url('conversations.history')).with(query: hash_including({}))
            .to_return(status: 200, body: { ok: false, error: 'missing_scope' }.to_json,
              headers: { 'Content-Type' => 'application/json' })
        end

        it 'still triggers the flow without channel context' do
          expect(captured_goal).to exclude('<channel_context>')
        end
      end

      context 'when only some of the channel history fits in the budget' do
        let(:channel_message_size) { slack_goal_max / 8 }

        let(:channel_history_response) do
          messages = Array.new(15) do |i|
            { user: 'U_CHANNEL', text: "m#{i} #{'x' * channel_message_size}", ts: "1234567880.0000#{15 - i}" }
          end

          { ok: true, messages: messages }
        end

        it 'keeps the newest messages that fit and drops the rest', :aggregate_failures do
          goal = captured_goal

          expect(goal).to include('<channel_context>')
          expect(goal.length).to be <= slack_goal_max
          expect(goal).to include('m0 ')
          expect(goal).to include('m3 ')
          expect(goal).to exclude('m10 ')
          expect(goal).to exclude('m14 ')
        end

        it 'fills the budget to within one message of the limit' do
          goal = captured_goal

          expect(slack_goal_max - goal.length).to be < channel_message_size
        end
      end

      context 'when even a single channel message would push the goal over the budget' do
        let(:channel_history_response) do
          {
            ok: true,
            messages: [{ user: 'U_CHANNEL', text: 'c' * (slack_goal_max + 1_000), ts: '1234567880.000001' }]
          }
        end

        it 'keeps the goal without channel context', :aggregate_failures do
          goal = captured_goal

          expect(goal).to exclude('<channel_context>')
          expect(goal.length).to be <= slack_goal_max
        end
      end
    end

    describe 'goal truncation' do
      context 'when the thread is small enough to fit within SLACK_GOAL_MAX' do
        it 'returns the goal unchanged (no truncation)', :aggregate_failures do
          captured_goal = nil

          expect(mock_adapter).to receive(:trigger) do |bundle|
            captured_goal = bundle.goal
            trigger_result
          end

          execute

          expect(captured_goal.length).to be <= slack_goal_max
          expect(captured_goal).to include('<conversation>')
        end
      end

      context 'when the thread would produce a goal exceeding the goal limit' do
        # Size each message at a third of the limit; four of them plus overhead
        # exceed the budget while any single message still fits.
        let(:big_text) { 'y' * (slack_goal_max / 3) }
        let(:thread_replies_response) do
          {
            ok: true,
            messages: [
              { user: slack_user_id, text: "oldest #{big_text}", ts: '1000.000001' },
              { user: 'U_OTHER', text: big_text, ts: '1000.000002' },
              { user: 'U_OTHER', text: big_text, ts: '1000.000003' },
              { user: slack_user_id, text: "newest ask #{big_text}", ts: '1000.000004' }
            ]
          }
        end

        it 'truncates newest-first within budget, dropping the oldest with an omission marker', :aggregate_failures do
          captured_goal = nil

          expect(mock_adapter).to receive(:trigger) do |bundle|
            captured_goal = bundle.goal
            trigger_result
          end

          execute

          expect(captured_goal.length).to be <= slack_goal_max
          # Newest-first: the triggering message is kept, the oldest is dropped.
          expect(captured_goal).to include('newest ask')
          expect(captured_goal).to exclude('oldest')
          # An omission marker (XML comment) flags the dropped messages.
          expect(captured_goal).to include('omitted due to length')
          expect(captured_goal).to include('<!--')
        end
      end

      context 'when the triggering message alone exceeds the budget' do
        let(:huge_text) { 'z' * (slack_goal_max + 1) }
        let(:thread_replies_response) do
          {
            ok: true,
            messages: [
              { user: slack_user_id, text: huge_text, ts: '1000.000001' }
            ]
          }
        end

        it 'does not trigger the flow and delivers a :message_too_long error', :aggregate_failures do
          expect(mock_adapter).not_to receive(:trigger)
          expect(mock_adapter).to receive(:deliver_error).with(
            callback_context: anything,
            error: :message_too_long
          )

          execute

          expect(WebMock).to have_requested(:post, slack_api_url('reactions.add'))
            .with(body: hash_including('name' => 'x'))
        end

        it 'tracks the blocked mention with the message_too_long reason' do
          expect { execute }.to trigger_internal_events('block_slack_duo_mention').with(
            user: user, additional_properties: { property: 'message_too_long' }
          )
        end
      end

      context 'when assembly stops being exactly additive (fail-closed guard)' do
        before do
          # Pad every non-empty render so the re-rendered goal overflows the
          # budget computed from the unpadded empty-input probe.
          allow_next_instance_of(described_class) do |service|
            allow(service).to receive(:assemble_goal).and_wrap_original do |original, *args|
              text = args[1]
              original.call(*args) + (text.empty? ? '' : '!' * slack_goal_max)
            end
          end
        end

        it 'logs the overflow and delivers :message_too_long instead of an oversized goal', :aggregate_failures do
          expect(mock_adapter).not_to receive(:trigger)
          expect(::Gitlab::IntegrationsLogger).to receive(:error).with(
            hash_including(message: 'Duo Messaging: assembled goal exceeded the limit')
          )
          expect(mock_adapter).to receive(:deliver_error).with(
            callback_context: anything,
            error: :message_too_long
          )

          execute
        end
      end
    end

    # On the first mention for a namespace the duo-workspace project does not exist yet, so it is
    # created in the same job that then starts the flow. When adding the new service account to the
    # project, its membership is first checked, which caches NO_ACCESS in the request store.
    # Without a purge that stale value denies :create_pipeline and the flow fails with a generic Slack error.
    # This spec ensures that the member access cache purge in
    # ee/app/services/ai/catalog/item_consumers/create_service.rb still works correctly.
    describe 'first mention for a namespace with no workspace project', :request_store do
      let_it_be(:duo_group) do
        create(:group, owners: user).tap do |group|
          group.namespace_settings.update!(duo_foundational_flows_enabled: true)
        end
      end

      let_it_be(:duo_service_account) do
        create(:user, :ai_service_account, provisioned_by_group: duo_group)
      end

      let_it_be(:foundational_flow) { create(:ai_catalog_foundational_flow, :developer, :with_item) }
      let_it_be(:catalog_item) { foundational_flow.catalog_item }

      let_it_be(:parent_item_consumer) do
        create(
          :ai_catalog_item_consumer,
          group: duo_group,
          item: catalog_item,
          service_account: duo_service_account,
          pinned_version_prefix: catalog_item.versions.first.version
        )
      end

      let_it_be(:enabled_flow) do
        create(:ai_catalog_enabled_foundational_flow, namespace: duo_group, catalog_item: catalog_item)
      end

      before do
        stub_licensed_features(ai_workflows: true, ai_features: true)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
        allow(user).to receive_messages(allowed_to_use?: true, default_duo_namespace: duo_group)

        allow(Ai::Messaging::DefaultProjectFlowResolver).to receive(:new).and_call_original
      end

      it 'creates the workspace project and grants the service account usable access' do
        expect { execute }.to change { duo_group.projects.count }.by(1)

        workspace_project = duo_group.projects.find_by_path('duo-workspace')

        expect(workspace_project.team.max_member_access(duo_service_account.id)).to eq(Member::DEVELOPER)

        expect(
          Ability.allowed?(duo_service_account, :create_pipeline, workspace_project, composite_identity_check: false)
        ).to be(true)
      end
    end
  end
end
