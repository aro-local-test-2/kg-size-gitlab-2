# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SyncSessionArtifactWorker, feature_category: :duo_agent_platform do
  describe '#perform' do
    let_it_be(:workflow) { create(:duo_workflows_workflow) }

    subject(:perform) { described_class.new.perform(workflow_id) }

    context 'when workflow exists' do
      let(:workflow_id) { workflow.id }

      it 'syncs the session artifact' do
        expect(Ai::DuoWorkflows::SessionArtifact).to receive(:sync_from_workflow!).with(workflow)

        perform
      end
    end

    context 'when workflow does not exist' do
      let(:workflow_id) { non_existing_record_id }

      it 'does not sync' do
        expect(Ai::DuoWorkflows::SessionArtifact).not_to receive(:sync_from_workflow!)

        perform
      end
    end

    context 'when workflow is a note-mention session (gitlab_duo_note)' do
      let_it_be(:note_mention_workflow) do
        create(:duo_workflows_workflow, messaging_callback_context: { 'adapter' => 'gitlab_duo_note', 'note_id' => 1 })
      end

      let(:workflow_id) { note_mention_workflow.id }

      it 'syncs the session artifact' do
        expect(Ai::DuoWorkflows::SessionArtifact).to receive(:sync_from_workflow!).with(note_mention_workflow)

        perform
      end

      it 'does not delete a previously synced artifact' do
        Ai::DuoWorkflows::SessionArtifact.sync_from_workflow!(note_mention_workflow)

        expect { perform }
          .not_to change { Ai::DuoWorkflows::SessionArtifact.for_workflow(note_mention_workflow.id).count }
      end
    end

    context 'when workflow is a private messaging session (slack)' do
      let_it_be(:messaging_workflow) do
        create(:duo_workflows_workflow, messaging_callback_context: { 'adapter' => 'slack' })
      end

      let(:workflow_id) { messaging_workflow.id }

      it 'does not sync' do
        expect(Ai::DuoWorkflows::SessionArtifact).not_to receive(:sync_from_workflow!)

        perform
      end
    end
  end
end
