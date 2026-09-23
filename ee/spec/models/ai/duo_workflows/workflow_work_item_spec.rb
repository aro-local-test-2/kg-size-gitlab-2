# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowWorkItem, feature_category: :duo_agent_platform do
  subject(:workflow_work_item) { build(:duo_workflows_workflow_work_item) }

  it_behaves_like 'a duo workflow link model with project_xor_namespace validation' do
    let(:link_model) { workflow_work_item }
  end

  it { is_expected.to belong_to(:workflow) }
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:namespace) }

  it { is_expected.to validate_presence_of(:workflow) }
  it { is_expected.to validate_presence_of(:work_item) }
  it { is_expected.to validate_presence_of(:link_type) }

  it 'defines the link_type enum' do
    is_expected.to define_enum_for(:link_type)
      .with_values(source: 0, created: 1)
      .with_prefix(:link_type)
  end

  describe '.links_workflow_to' do
    it 'derives the foreign key from the association name by default' do
      expect(described_class.workflow_artifact_association).to eq(:work_item)
      expect(described_class.workflow_artifact_foreign_key).to eq(:work_item_id)
    end

    it 'honors a custom foreign_key option over the association name' do
      klass = Class.new(ApplicationRecord) do
        self.table_name = :duo_workflows_workflow_work_items

        include Ai::DuoWorkflows::WorkflowLinkable

        links_workflow_to :artifact, class_name: 'WorkItem', foreign_key: :work_item_id, inverse_of: false
      end

      expect(klass.workflow_artifact_association).to eq(:artifact)
      expect(klass.workflow_artifact_foreign_key).to eq(:work_item_id)
    end
  end

  describe 'uniqueness' do
    it 'is enforced per workflow, work item, and link type by the database', :aggregate_failures do
      existing = create(:duo_workflows_workflow_work_item)

      duplicate = build(:duo_workflows_workflow_work_item,
        workflow: existing.workflow, work_item: existing.work_item, link_type: existing.link_type)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.ensure_link' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:work_item) { create(:work_item, project: project) }

    let(:artifact) { work_item }
    let(:link_type) { :source }
    let(:artifact_attr) { :work_item }

    it_behaves_like 'a duo workflow link model with ensure_link'

    it 'raises for an extra attribute the model does not have' do
      expect do
        described_class.ensure_link(workflow: workflow, artifact: work_item, link_type: :source,
          extra_attributes: { idempotency_key: 'no-such-column' })
      end.to raise_error(ActiveModel::UnknownAttributeError)
    end

    context 'when the workflow is namespace-scoped' do
      let_it_be(:group) { create(:group) }
      let_it_be(:workflow) { create(:duo_workflows_workflow, project: nil, namespace: group) }
      let_it_be(:work_item) { create(:work_item, :group_level, namespace: group) }

      subject(:errors) do
        described_class.ensure_link(workflow: workflow, artifact: work_item, link_type: :source)
      end

      it 'creates a link with the namespace set and project null' do
        expect { errors }.to change { described_class.count }.by(1)
        expect(errors).to be_empty

        expect(described_class.last).to have_attributes(
          workflow: workflow,
          work_item: work_item,
          project_id: nil,
          namespace_id: group.id,
          link_type: 'source'
        )
      end
    end
  end
end
