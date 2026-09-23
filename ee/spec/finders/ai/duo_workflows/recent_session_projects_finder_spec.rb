# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::RecentSessionProjectsFinder, feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:recent_project) { create(:project, :private, group: group, developers: user) }
  let_it_be(:older_project) { create(:project, :private, group: group, developers: user) }

  let(:current_user) { user }
  let(:limit) { described_class::MAX_PROJECTS }

  subject(:projects) { described_class.new(current_user: current_user, limit: limit).execute }

  context 'with sessions in two projects' do
    before_all do
      create(:duo_workflows_workflow, project: older_project, user: user, updated_at: 2.days.ago)
      create_list(:duo_workflows_workflow, 2, project: recent_project, user: user, updated_at: 1.hour.ago)
    end

    it 'returns each project once, most recent session first' do
      expect(projects).to eq([recent_project, older_project])
    end

    context 'when there are more projects than the limit' do
      let(:limit) { 1 }

      it 'returns only the most recent projects' do
        expect(projects).to eq([recent_project])
      end
    end

    it 'runs a fixed number of queries however many sessions and projects there are' do
      control = ActiveRecord::QueryRecorder.new { projects.to_a }

      create(:duo_workflows_workflow, project: create(:project, :private, group: group, developers: user), user: user)

      expect { described_class.new(current_user: current_user, limit: limit).execute.to_a }
        .not_to exceed_query_limit(control)
    end
  end

  context 'without a current user' do
    let(:current_user) { nil }

    it 'returns nothing' do
      create(:duo_workflows_workflow, project: recent_project, user: user)

      expect(projects).to be_empty
    end
  end

  it 'excludes projects the user only has foundational chat sessions in' do
    create(:duo_workflows_workflow, :agentic_chat, project: recent_project, user: user)

    expect(projects).to be_empty
  end

  it 'excludes sessions belonging to other users' do
    create(:duo_workflows_workflow, project: recent_project, user: create(:user))

    expect(projects).to be_empty
  end

  it 'excludes namespace-level sessions, which have no project' do
    create(:duo_workflows_workflow, project: nil, namespace: group, user: user)

    expect(projects).to be_empty
  end

  it 'excludes projects the user can no longer read' do
    create(:duo_workflows_workflow, project: create(:project, :private), user: user)

    expect(projects).to be_empty
  end
end
