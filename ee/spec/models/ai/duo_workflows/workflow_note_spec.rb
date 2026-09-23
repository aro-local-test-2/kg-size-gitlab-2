# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowNote, feature_category: :duo_agent_platform do
  subject(:workflow_note) { build(:duo_workflows_workflow_note) }

  it_behaves_like 'a duo workflow link model with project_xor_namespace validation' do
    let(:link_model) { workflow_note }
  end

  it { is_expected.to belong_to(:workflow) }
  it { is_expected.to belong_to(:note) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:namespace) }

  it { is_expected.to validate_presence_of(:workflow) }
  it { is_expected.to validate_presence_of(:note) }
  it { is_expected.to validate_presence_of(:link_type) }

  it 'defines the link_type enum' do
    is_expected.to define_enum_for(:link_type)
      .with_values(created: 1, triggered: 2)
      .with_prefix(:link_type)
  end

  describe 'uniqueness' do
    it 'is enforced per workflow, note, and link type by the database', :aggregate_failures do
      existing = create(:duo_workflows_workflow_note)

      duplicate = build(:duo_workflows_workflow_note,
        workflow: existing.workflow, note: existing.note, link_type: existing.link_type)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.for_workflows' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:link) { create(:duo_workflows_workflow_note, workflow: workflow, note: create(:note, project: project)) }

    before_all do
      create(:duo_workflows_workflow_note, workflow: other_workflow, note: create(:note, project: project))
    end

    it 'accepts a relation and returns the links of those workflows only' do
      expect(described_class.for_workflows(::Ai::DuoWorkflows::Workflow.id_in(workflow.id))).to contain_exactly(link)
    end
  end

  describe '.created_for_notes_ordered' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }

    let_it_be(:note_a) { create(:note, project: project) }
    let_it_be(:note_b) { create(:note, project: project) }

    let_it_be(:created_a) do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note_a, link_type: :created)
    end

    let_it_be(:created_b) do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note_b, link_type: :created)
    end

    before_all do
      note_c = create(:note, project: project)
      create(:duo_workflows_workflow_note, workflow: workflow, note: note_c, link_type: :triggered)
    end

    it 'returns only created links matching the given note IDs, excluding other link types and IDs' do
      expect(described_class.created_for_notes_ordered([note_a.id])).to contain_exactly(created_a)
    end

    it 'orders oldest link first so the resolved session matches duo_created_workflow_link' do
      later_workflow = create(:duo_workflows_workflow, project: project)
      create(:duo_workflows_workflow_note, workflow: later_workflow, note: note_a, link_type: :created)

      expect(described_class.created_for_notes_ordered([note_a.id]).first).to eq(created_a)
    end

    it 'preloads the workflow used to authorize the session' do
      result = described_class.created_for_notes_ordered([note_a.id, note_b.id]).load

      expect { result.map(&:workflow) }.not_to exceed_query_limit(0)
    end

    it 'preloads the parent used to authorize namespace-level sessions' do
      group = create(:group)
      namespace_workflow = create(:duo_workflows_workflow, project: nil, namespace: group)
      note_d = create(:note, project: project)
      create(:duo_workflows_workflow_note,
        workflow: namespace_workflow, note: note_d, project: nil, namespace: group, link_type: :created)

      result = described_class.created_for_notes_ordered([note_d.id]).load

      expect { result.map { |link| link.workflow.resource_parent } }.not_to exceed_query_limit(0)
    end
  end

  describe '.triggered_for_notes' do
    let_it_be(:project) { create(:project) }
    let_it_be(:catalog_item_version) { create(:ai_catalog_item_version) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: project, ai_catalog_item_version: catalog_item_version)
    end

    let_it_be(:note_a) { create(:note, project: project) }
    let_it_be(:note_b) { create(:note, project: project) }
    let_it_be(:triggered_a) do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note_a, link_type: :triggered)
    end

    let_it_be(:triggered_b) do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note_b, link_type: :triggered)
    end

    before_all do
      note_c = create(:note, project: project)
      create(:duo_workflows_workflow_note, workflow: workflow, note: note_c, link_type: :created)
    end

    it 'returns only triggered links matching the given note IDs, excluding other link types and IDs' do
      # triggered_b exists but is excluded by the note_id filter; created_c is excluded by link_type
      expect(described_class.triggered_for_notes([note_a.id])).to contain_exactly(triggered_a)
    end

    it 'preloads associations used to resolve the agent name and authorize the workflow' do
      result = described_class.triggered_for_notes([note_a.id, note_b.id]).load

      expect do
        result.map { |link| ::Ai::DuoWorkflows::WorkflowPresenter.new(link.workflow).agent_name }
        result.map { |link| link.workflow.user }
      end.not_to exceed_query_limit(0)
    end
  end

  describe '.ensure_link' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:note) { create(:note, project: project) }

    let(:artifact) { note }
    let(:link_type) { :created }
    let(:artifact_attr) { :note }

    it_behaves_like 'a duo workflow link model with ensure_link'
  end
end
