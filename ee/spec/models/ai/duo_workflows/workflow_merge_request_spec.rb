# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowMergeRequest, feature_category: :duo_agent_platform do
  subject(:workflow_merge_request) { build(:duo_workflows_workflow_merge_request) }

  it_behaves_like 'a duo workflow link model with project_xor_namespace validation' do
    let(:link_model) { workflow_merge_request }
  end

  it { is_expected.to belong_to(:workflow) }
  it { is_expected.to belong_to(:merge_request) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:namespace) }

  it { is_expected.to validate_presence_of(:workflow) }
  it { is_expected.to validate_presence_of(:merge_request) }
  it { is_expected.to validate_presence_of(:link_type) }
  it { is_expected.to validate_length_of(:idempotency_key).is_at_most(255) }

  it 'defines the link_type enum' do
    is_expected.to define_enum_for(:link_type)
      .with_values(source: 0, created: 1)
      .with_prefix(:link_type)
  end

  describe 'uniqueness' do
    it 'is enforced per workflow, merge request, and link type by the database', :aggregate_failures do
      existing = create(:duo_workflows_workflow_merge_request)

      duplicate = build(:duo_workflows_workflow_merge_request,
        workflow: existing.workflow, merge_request: existing.merge_request, link_type: existing.link_type)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '.ensure_link' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let(:artifact) { merge_request }
    let(:link_type) { :source }
    let(:artifact_attr) { :merge_request }

    it_behaves_like 'a duo workflow link model with ensure_link'

    context 'with extra attributes' do
      subject(:errors) do
        described_class.ensure_link(workflow: workflow, artifact: merge_request, link_type: :created,
          extra_attributes: { idempotency_key: 'fix-pipeline-broken-spec' })
      end

      it 'stores the attributes on the link' do
        expect(errors).to be_empty
        expect(described_class.order(:id).last.idempotency_key).to eq('fix-pipeline-broken-spec')
      end
    end
  end

  describe '.idempotency_key_for' do
    let_it_be(:project) { create(:project) }

    it 'derives the key from the flow definition and the source pipeline ref' do
      workflow = create(:duo_workflows_workflow, project: project, workflow_definition: 'fix_pipeline/v1')
      pipeline = create(:ci_pipeline, project: project, ref: 'master')
      create(:duo_workflows_workflow_pipeline, workflow: workflow, pipeline: pipeline)

      expect(described_class.idempotency_key_for(workflow))
        .to eq("fix_pipeline/v1:pipeline-ref-sha:#{Digest::SHA256.hexdigest('master')}")
    end

    it 'returns nil for a workflow without a source pipeline' do
      workflow = create(:duo_workflows_workflow, project: project, workflow_definition: 'fix_pipeline/v1')

      expect(described_class.idempotency_key_for(workflow)).to be_nil
    end

    it 'returns nil for a flow that does not opt into reuse_open_merge_request' do
      workflow = create(:duo_workflows_workflow, project: project, workflow_definition: 'developer/v1')
      pipeline = create(:ci_pipeline, project: project)
      create(:duo_workflows_workflow_pipeline, workflow: workflow, pipeline: pipeline)

      expect(described_class.idempotency_key_for(workflow)).to be_nil
    end
  end

  describe '.open_merge_request_for' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let_it_be(:link) do
      create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: merge_request,
        link_type: :created, idempotency_key: 'fix-pipeline-broken-spec')
    end

    it 'returns the open merge request recorded under the key' do
      expect(described_class.open_merge_request_for(project.id, 'fix-pipeline-broken-spec')).to eq(merge_request)
    end

    it 'returns nil for an unknown key' do
      expect(described_class.open_merge_request_for(project.id, 'other-key')).to be_nil
    end

    it 'returns nil for another project' do
      expect(described_class.open_merge_request_for(project.id + 1, 'fix-pipeline-broken-spec')).to be_nil
    end

    it 'returns nil when the recorded merge request is merged' do
      merged = create(:merge_request, :merged, source_project: project, source_branch: 'feature-merged',
        target_branch: 'master')
      create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: merged,
        link_type: :created, idempotency_key: 'merged-key')

      expect(described_class.open_merge_request_for(project.id, 'merged-key')).to be_nil
    end

    it 'returns nil when the recorded merge request is no longer open' do
      closed = create(:merge_request, :closed, source_project: project, source_branch: 'feature',
        target_branch: 'master')
      create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: closed,
        link_type: :created, idempotency_key: 'closed-key')

      expect(described_class.open_merge_request_for(project.id, 'closed-key')).to be_nil
    end
  end
end
