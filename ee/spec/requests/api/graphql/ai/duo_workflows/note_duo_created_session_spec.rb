# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Note.duoCreatedSession', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }
  let_it_be(:note) { create(:note, project: project, noteable: issue) }

  let(:current_user) { user }

  let(:query) do
    <<~GRAPHQL
      query {
        note(id: "#{note.to_gid}") {
          id
          duoCreatedSession { id }
        }
      }
    GRAPHQL
  end

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true) # rubocop:disable RSpec/AnyInstanceOf -- current_user identity differs across the request
  end

  subject(:duo_created_session) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:note, :duo_created_session)
  end

  it 'is null when the note has no session' do
    expect(duo_created_session).to be_nil
    expect(graphql_errors).to be_nil
  end

  context 'when the session created the note' do
    before do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note, link_type: :created)
    end

    it 'returns the session' do
      expect(duo_created_session).to eq('id' => workflow.to_gid.to_s)
    end
  end

  context 'when the requesting user cannot read the session' do
    let_it_be(:other_member) { create(:user, developer_of: project) }

    let(:current_user) { other_member }

    before do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note, link_type: :created)
    end

    it 'is null even though the note itself is readable' do
      expect(duo_created_session).to be_nil
      expect(graphql_data_at(:note, :id)).to eq(note.to_gid.to_s)
    end
  end

  context 'when the session ran in the web environment' do
    let_it_be(:other_member) { create(:user, developer_of: project) }
    let_it_be(:web_workflow) { create(:duo_workflows_workflow, project: project, environment: :web) }
    let_it_be(:web_note) { create(:note, project: project, noteable: issue) }

    let(:current_user) { other_member }

    let(:query) do
      <<~GRAPHQL
        query {
          note(id: "#{web_note.to_gid}") {
            id
            duoCreatedSession { id }
          }
        }
      GRAPHQL
    end

    before_all do
      create(:duo_workflows_workflow_note, workflow: web_workflow, note: web_note, link_type: :created)
    end

    it 'returns the session to any project member' do
      expect(duo_created_session).to eq('id' => web_workflow.to_gid.to_s)
    end
  end

  context 'when there is no current user' do
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:public_issue) { create(:issue, project: public_project) }
    let_it_be(:public_note) { create(:note, project: public_project, noteable: public_issue) }
    let_it_be(:public_workflow) do
      create(:duo_workflows_workflow, project: public_project, environment: :web)
    end

    let(:current_user) { nil }

    let(:query) do
      <<~GRAPHQL
        query {
          note(id: "#{public_note.to_gid}") {
            id
            duoCreatedSession { id }
          }
        }
      GRAPHQL
    end

    before_all do
      create(:duo_workflows_workflow_note, workflow: public_workflow, note: public_note, link_type: :created)
    end

    it 'is null for anonymous users even though the note is readable' do
      expect(duo_created_session).to be_nil
      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:note, :id)).to eq(public_note.to_gid.to_s)
    end
  end

  describe 'granular PAT authorization' do
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:public_issue) { create(:issue, project: public_project) }
    let_it_be(:public_note) { create(:note, project: public_project, noteable: public_issue) }
    let_it_be(:public_workflow) { create(:duo_workflows_workflow, project: public_project, user: user) }

    let_it_be(:public_link) do
      create(:duo_workflows_workflow_note, workflow: public_workflow, note: public_note, link_type: :created)
    end

    let(:query) { graphql_query_for(:note, { id: public_note.to_gid }, 'duoCreatedSession { id }') }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(public_project, :duo_workflow).and_return(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  describe 'across a list of notes' do
    let(:list_query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            issue(iid: "#{issue.iid}") {
              notes { nodes { id duoCreatedSession { id } } }
            }
          }
        }
      GRAPHQL
    end

    it 'does not issue queries per note' do
      link_session_to(create(:note, project: project, noteable: issue), session: workflow)
      link_session_to(create(:note, project: project, noteable: issue))
      post_graphql(list_query, current_user: user)

      control = ActiveRecord::QueryRecorder.new { post_graphql(list_query, current_user: user) }

      3.times { link_session_to(create(:note, project: project, noteable: issue)) }

      expect { post_graphql(list_query, current_user: user) }.not_to exceed_query_limit(control)
      expect(graphql_data_at(:project, :issue, :notes, :nodes).pluck('duoCreatedSession').compact).to be_present
    end

    def link_session_to(new_note, session: nil)
      session ||= create(:duo_workflows_workflow, project: project, user: create(:user, developer_of: project))
      create(:duo_workflows_workflow_note, workflow: session, note: new_note, link_type: :created)
    end
  end
end
