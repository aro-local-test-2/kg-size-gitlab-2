# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowPipeline, feature_category: :duo_agent_platform do
  subject(:workflow_pipeline) { build(:duo_workflows_workflow_pipeline) }

  it_behaves_like 'a duo workflow link model with project_xor_namespace validation' do
    let(:link_model) { workflow_pipeline }
  end

  it { is_expected.to belong_to(:workflow) }
  it { is_expected.to belong_to(:pipeline) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:namespace) }

  it { is_expected.to validate_presence_of(:workflow) }
  it { is_expected.to validate_presence_of(:pipeline) }
  it { is_expected.to validate_presence_of(:link_type) }

  it 'defines the link_type enum' do
    is_expected.to define_enum_for(:link_type)
      .with_values(source: 0)
      .with_prefix(:link_type)
  end

  describe 'uniqueness' do
    it 'is enforced per workflow, pipeline, and link type by the database', :aggregate_failures do
      existing = create(:duo_workflows_workflow_pipeline)

      duplicate = build(:duo_workflows_workflow_pipeline,
        workflow: existing.workflow, pipeline: existing.pipeline, link_type: existing.link_type)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.for_pipelines' do
    let_it_be(:link) { create(:duo_workflows_workflow_pipeline) }
    let_it_be(:other_link) { create(:duo_workflows_workflow_pipeline) }

    it 'returns the links for the given pipelines' do
      expect(described_class.for_pipelines([link.pipeline_id])).to contain_exactly(link)
    end

    it 'accepts several pipelines at once' do
      expect(described_class.for_pipelines([link.pipeline_id, other_link.pipeline_id]))
        .to contain_exactly(link, other_link)
    end
  end

  describe '.ensure_link' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

    let(:artifact) { pipeline }
    let(:link_type) { :source }
    let(:artifact_attr) { :pipeline }

    it_behaves_like 'a duo workflow link model with ensure_link'
  end
end
