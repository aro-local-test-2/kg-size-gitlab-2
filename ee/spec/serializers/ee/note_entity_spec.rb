# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NoteEntity do
  include Gitlab::Routing

  let_it_be(:issue, freeze: false) { create(:issue) }
  let_it_be(:description_version) { create(:description_version, issue: issue) }
  let_it_be(:system_note_metadata, freeze: false) { create(:system_note_metadata, description_version: description_version) }
  let_it_be(:system_note, freeze: false) do
    create(:system_note, project: issue.project, noteable: issue, system_note_metadata: system_note_metadata)
  end

  let_it_be(:plain_note) do
    create(:note, project: issue.project, noteable: issue)
  end

  let(:note) { plain_note }
  let(:request) { double('request', current_user: issue.author, noteable: issue) }
  let(:entity) { described_class.new(note, request: request) }

  subject { entity.as_json }

  describe 'duo session fields on non-system notes', feature_category: :duo_agent_platform do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: issue.project, environment: :web) }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
      issue.project.project_setting.update!(duo_features_enabled: true)
    end

    context 'when the note has a triggered workflow link' do
      let_it_be(:triggering_note) { create(:note, project: issue.project, noteable: issue) }
      let(:note) { triggering_note }

      before_all do
        create(:duo_workflows_workflow_note, workflow: workflow, note: triggering_note, link_type: :triggered)
      end

      it 'exposes duo session fields from the triggered workflow', :aggregate_failures do
        presenter = ::Ai::DuoWorkflows::WorkflowPresenter.new(workflow)

        expect(subject[:duo_session_id_triggered]).to eq(workflow.to_global_id)
        expect(subject[:duo_session_agent_name]).to eq(presenter.agent_name)
        expect(subject[:duo_session_status]).to eq(workflow.status_name)
        expect(subject[:duo_session_status]).not_to eq(workflow.status)
      end

      context 'when the current user cannot read the triggered workflow' do
        let_it_be(:outsider) { create(:user) }

        let(:request) { double('request', current_user: outsider, noteable: issue) }

        it 'omits all triggered duo session fields', :aggregate_failures do
          expect(subject[:duo_session_id_triggered]).to be_nil
          expect(subject[:duo_session_agent_name]).to be_nil
          expect(subject[:duo_session_status]).to be_nil
        end
      end
    end

    context 'when the note has no triggered workflow link' do
      it 'exposes duo session fields as nil for a plain note', :aggregate_failures do
        expect(subject[:duo_session_id_triggered]).to be_nil
        expect(subject[:duo_session_agent_name]).to be_nil
        expect(subject[:duo_session_status]).to be_nil
      end

      context 'when the note has a created (agent-reply) link instead' do
        let_it_be(:reply_note) { create(:note, project: issue.project, noteable: issue) }
        let(:note) { reply_note }

        before_all do
          create(:duo_workflows_workflow_note, workflow: workflow, note: reply_note, link_type: :created)
        end

        it 'exposes duo session fields as nil', :aggregate_failures do
          expect(subject[:duo_session_id_triggered]).to be_nil
          expect(subject[:duo_session_agent_name]).to be_nil
          expect(subject[:duo_session_status]).to be_nil
        end
      end
    end

    context 'when the note is a system note' do
      let(:note) { system_note }

      it 'omits all duo session fields', :aggregate_failures do
        expect(subject.key?(:duo_session_id_triggered)).to be false
        expect(subject.key?(:duo_session_agent_name)).to be false
        expect(subject.key?(:duo_session_status)).to be false
      end
    end
  end

  describe 'duo_session_id', feature_category: :duo_agent_platform do
    # Note-triggered flows run in the web environment, which WorkflowPolicy treats as
    # from_pipeline? and grants to any project member with Duo access.
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: issue.project, environment: :web)
    end

    let_it_be(:duo_metadata) do
      create(:note_duo_metadata, note: plain_note, workflow_id: workflow.id, namespace_id: issue.namespace_id)
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
      issue.project.project_setting.update!(duo_features_enabled: true)
    end

    context 'when the current user cannot read the session' do
      let_it_be(:outsider) { create(:user) }

      let(:request) { double('request', current_user: outsider, noteable: issue) }

      it 'omits duo_session_id so the frontend does not offer a session it cannot open' do
        expect(subject.key?(:duo_session_id)).to be false
      end

      context 'when the note is linked through a created workflow_note' do
        let_it_be(:unauthorized_linked_note) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { unauthorized_linked_note }

        before_all do
          ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
            workflow: workflow, artifact: unauthorized_linked_note, link_type: :created
          )
        end

        it 'omits duo_session_id' do
          expect(subject.key?(:duo_session_id)).to be false
        end
      end
    end

    context 'when there is no current user' do
      let(:request) { double('request', current_user: nil, noteable: issue) }

      it 'omits duo_session_id for anonymous users' do
        expect(subject.key?(:duo_session_id)).to be false
      end
    end

    context 'when the note is not a system note' do
      it 'exposes the workflow id as duo_session_id' do
        expect(subject[:duo_session_id]).to eq(workflow.id)
      end

      context 'when the note has no duo_metadata' do
        let_it_be(:note_without_metadata) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { note_without_metadata }

        it 'exposes duo_session_id as nil' do
          expect(subject[:duo_session_id]).to be_nil
        end

        it 'omits the key entirely rather than sending null on every note' do
          expect(subject.key?(:duo_session_id)).to be false
        end
      end

      context 'when the note is linked to a workflow through a created workflow_note' do
        let_it_be(:linked_note) { create(:note, project: issue.project, noteable: issue) }

        let(:note) { linked_note }

        before_all do
          ::Ai::DuoWorkflows::WorkflowNote.ensure_link(
            workflow: workflow, artifact: linked_note, link_type: :created
          )
        end

        it 'falls back to the linked workflow id' do
          expect(subject[:duo_session_id]).to eq(workflow.id)
        end
      end
    end

    context 'when the note is a system note' do
      let(:note) { system_note }

      it 'does not expose duo_session_id' do
        expect(subject.key?(:duo_session_id)).to be false
      end
    end

    context 'when the note is a duo_mention_started system note' do
      let_it_be(:duo_mention_note) do
        create(:system_note, project: issue.project, noteable: issue,
          system_note_metadata: create(:system_note_metadata, action: 'duo_mention_started'))
      end

      let_it_be(:duo_mention_metadata) do
        create(:note_duo_metadata, note: duo_mention_note, workflow_id: workflow.id,
          namespace_id: issue.namespace_id)
      end

      let(:note) { duo_mention_note }

      it 'exposes the workflow id as duo_session_id' do
        expect(subject[:duo_session_id]).to eq(workflow.id)
      end
    end
  end

  describe 'duo session fields on duo_mention_started system notes', feature_category: :duo_code_review do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: issue.project, environment: :web) }

    # Use a dedicated system note so we don't conflict with the top-level
    # system_note_metadata (which already occupies the unique slot on system_note).
    let_it_be(:duo_mention_note) do
      create(:system_note, project: issue.project, noteable: issue,
        system_note_metadata: create(:system_note_metadata, action: 'duo_mention_started'))
    end

    let(:note) { duo_mention_note }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(issue.project, :duo_workflow).and_return(true)
      allow(issue.author).to receive(:allowed_to_use?).and_return(true)
      issue.project.project_setting.update!(duo_features_enabled: true)
    end

    before_all do
      create(:note_duo_metadata, note: duo_mention_note, workflow_id: workflow.id,
        namespace_id: issue.namespace_id)
    end

    it 'exposes duo session fields from the linked workflow', :aggregate_failures do
      presenter = ::Ai::DuoWorkflows::WorkflowPresenter.new(workflow)

      expect(subject[:duo_session_id]).to eq(workflow.id)
      expect(subject[:duo_session_agent_name]).to eq(presenter.agent_name)
      expect(subject[:duo_session_status]).to eq(workflow.status_name)
      expect(subject[:duo_session_status]).not_to eq(workflow.status)
    end

    context 'when the current user cannot read the workflow' do
      let_it_be(:outsider) { create(:user) }

      let(:request) { double('request', current_user: outsider, noteable: issue) }

      it 'omits duo session fields', :aggregate_failures do
        expect(subject[:duo_session_agent_name]).to be_nil
        expect(subject[:duo_session_status]).to be_nil
      end
    end

    context 'when the duo_mention_started note has no duo_metadata' do
      let_it_be(:bare_duo_mention_note) do
        create(:system_note, project: issue.project, noteable: issue,
          system_note_metadata: create(:system_note_metadata, action: 'duo_mention_started'))
      end

      let(:note) { bare_duo_mention_note }

      it 'exposes duo session fields as nil', :aggregate_failures do
        expect(subject[:duo_session_agent_name]).to be_nil
        expect(subject[:duo_session_status]).to be_nil
      end
    end

    context 'when the system note has a different action' do
      let(:note) { system_note }

      it 'omits all duo session fields', :aggregate_failures do
        expect(subject.key?(:duo_session_id)).to be false
        expect(subject.key?(:duo_session_agent_name)).to be false
        expect(subject.key?(:duo_session_status)).to be false
      end
    end
  end

  describe 'description versions', feature_category: :team_planning do
    let(:note) { system_note }

    context 'when description_diffs license is available' do
      before do
        stub_licensed_features(description_diffs: true)
      end

      it 'includes description versions attributes' do
        expect(subject[:description_version_id]).to eq(description_version.id)
        expect(subject[:description_diff_path]).to eq(description_diff_project_issue_path(issue.project, issue, description_version.id))
        expect(subject[:delete_description_version_path]).to eq(delete_description_version_project_issue_path(issue.project, issue, description_version.id))
        expect(subject[:can_delete_description_version]).to be(true)
      end
    end

    context 'when description_diffs license is not available' do
      before do
        stub_licensed_features(description_diffs: false)
      end

      it 'does not include description versions attributes' do
        expect(subject[:description_version_id]).to be_nil
        expect(subject[:description_diff_path]).to be_nil
        expect(subject[:delete_description_version_path]).to be_nil
        expect(subject[:can_delete_description_version]).to be_nil
      end
    end
  end
end
