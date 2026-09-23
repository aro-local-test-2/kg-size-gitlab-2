# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying the branches of a Duo Agent Platform turn', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: group) }
  let_it_be(:another_user) { create(:user, developer_of: group) }

  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, project: project, user: user, incremental_checkpoints_enabled: true)
  end

  # Say 2 was retried as Say 3, so both attempts hang off the answer to Say 1. The
  # abandoned attempt ends on a settled checkpoint that added no message.
  let_it_be(:tree) do
    {
      'ts-1' => { parent: nil, message: ['Say 1', 'user'], version: '1' },
      'ts-a1' => { parent: 'ts-1', message: %w[1 agent], version: '2' },
      'ts-b1' => { parent: 'ts-a1', message: ['Say 2', 'user'], version: '3' },
      'ts-b2' => { parent: 'ts-b1', message: %w[2 agent], version: '4' },
      'ts-b3' => { parent: 'ts-b2', status: 'input_required', version: '5' },
      'ts-c1' => { parent: 'ts-a1', message: ['Say 3', 'user'], version: '3' },
      'ts-c2' => { parent: 'ts-c1', message: %w[3 agent], version: '4' }
    }
  end

  let(:current_user) { user }
  let(:thread_ts) { 'ts-c1' }
  let(:query) do
    graphql_query_for(
      'duoWorkflowBranches',
      { workflow_id: workflow.to_global_id.to_s, thread_ts: thread_ts },
      <<~GRAPHQL
        forkThreadTs
        messages {
          content
          messageType
          threadTs
          parentTs
          alternativeCount
        }
      GRAPHQL
    )
  end

  subject(:branches) { graphql_data['duoWorkflowBranches'] }

  before_all do
    tree.each do |thread_ts, node|
      create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
        thread_ts: thread_ts, parent_ts: node[:parent], current_thread: 0)

      channel, value =
        if node[:message]
          ['ui_chat_log', [{ 'content' => node[:message].first, 'message_type' => node[:message].last }]]
        else
          ['status', node[:status]]
        end

      create(:duo_workflows_checkpoint_blob, workflow: workflow, project: project, thread_ts: thread_ts,
        current_thread: 0, channel: channel, version: node[:version], step_action: 'conversation',
        data: Zlib::Deflate.deflate(Gitlab::Json.dump(value)))
    end
  end

  before do
    stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_graphql: project)
    # read_duo_workflow needs :duo_workflow on the project, which checks the stage and
    # the user's seat; ownership of the session is what the policy narrows on.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(any_args).and_return(true)
    # The seat is read off the user the request authenticates, which is loaded from the
    # database rather than being the record built here.
    allow_next_found_instance_of(User) do |found_user|
      allow(found_user).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
    end
  end

  it 'returns the abandoned attempt with its messages and the checkpoint to resume it from', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_nil

    expect(branches.size).to eq(1)
    expect(branches.first['forkThreadTs']).to eq('ts-b3')
    expect(branches.first['messages'].pluck('content')).to eq(['Say 2', '2'])
  end

  it 'skips a chat log entry that is not a message, rather than failing the query', :aggregate_failures do
    # The fold carries whatever the gateway wrote, and the checkpoint read skips
    # non-messages too.
    create(:duo_workflows_checkpoint_blob, workflow: workflow, project: project, thread_ts: 'ts-b2',
      current_thread: 0, channel: 'ui_chat_log', version: '6', step_action: 'conversation',
      data: Zlib::Deflate.deflate(Gitlab::Json.dump(['not a message'])))

    post_graphql(query, current_user: current_user)

    expect(graphql_errors).to be_nil
    expect(branches.first['messages'].pluck('content')).to eq(['Say 2', '2'])
  end

  it 'stamps the alternative messages, so the client can fork from them in turn' do
    post_graphql(query, current_user: current_user)

    expect(branches.first['messages'].first).to include(
      'threadTs' => 'ts-b1', 'parentTs' => 'ts-a1', 'alternativeCount' => 1
    )
  end

  it 'excludes the branch the given message belongs to' do
    post_graphql(query, current_user: current_user)

    expect(branches.flat_map { |branch| branch['messages'].pluck('content') }).to exclude('Say 3', '3')
  end

  it 'returns nothing for a checkpoint that anchors no retried turn' do
    post_graphql(
      graphql_query_for('duoWorkflowBranches',
        { workflow_id: workflow.to_global_id.to_s, thread_ts: 'ts-1' }, 'forkThreadTs'),
      current_user: current_user
    )

    expect(graphql_data['duoWorkflowBranches']).to eq([])
  end

  context 'when the message was abandoned by a retry' do
    let(:thread_ts) { 'ts-b1' }

    it 'returns an error, since an abandoned message can have alternatives that branch further' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include(/ts-b1 is not on the current branch/)
    end
  end

  context 'when the graphql consumer flag is off' do
    before do
      stub_feature_flags(dw_read_blobs_graphql: false)
    end

    it 'returns nothing, since messages are not reconstructed from blobs' do
      post_graphql(query, current_user: current_user)

      expect(branches).to eq([])
    end
  end

  context 'when the session does not store incremental checkpoints' do
    before do
      workflow.update!(incremental_checkpoints_enabled: false)
    end

    it 'returns nothing' do
      post_graphql(query, current_user: current_user)

      expect(branches).to eq([])
    end
  end

  context 'when the user cannot read the session' do
    let(:current_user) { another_user }

    it 'answers as though the session does not exist, so a wrong id is not read as no branches' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include(/does not exist or you don't have permission/)
    end
  end

  context 'when the user is not logged in' do
    it 'answers as though the session does not exist' do
      post_graphql(query, current_user: nil)

      expect_graphql_errors_to_include(/does not exist or you don't have permission/)
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow do
    let(:boundary_object) { :user }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end

  context 'when querying the branch type' do
    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
      let(:skipped_data_path) { [:duo_workflow_branches] }
    end
  end

  context 'when querying the message type' do
    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
      let(:skipped_data_path) { [:duo_workflow_branches, 0, :messages] }
    end
  end
end
