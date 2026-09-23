# frozen_string_literal: true

# Shared examples for the `#project_xor_namespace_present` validation common to all
# Ai::DuoWorkflows workflow-link join models (WorkflowWorkItem, WorkflowMergeRequest,
# WorkflowPipeline, WorkflowNote).
#
# Requires the caller to define a `link_model` instance that responds to `assign_attributes`.
RSpec.shared_examples 'a duo workflow link model with project_xor_namespace validation' do
  describe '#project_xor_namespace_present' do
    it 'is valid with only a project' do
      link_model.assign_attributes(project: build_stubbed(:project), namespace: nil)

      expect(link_model).to be_valid
    end

    it 'is valid with only a namespace' do
      link_model.assign_attributes(project: nil, namespace: build_stubbed(:group))

      expect(link_model).to be_valid
    end

    it 'is invalid without a project or namespace', :aggregate_failures do
      link_model.assign_attributes(project: nil, namespace: nil)

      expect(link_model).to be_invalid
      expect(link_model.errors[:base]).to include('either project_id or namespace_id must be present')
    end

    it 'is invalid with both a project and a namespace', :aggregate_failures do
      link_model.assign_attributes(project: build_stubbed(:project), namespace: build_stubbed(:group))

      expect(link_model).to be_invalid
      expect(link_model.errors[:base]).to include('either project_id or namespace_id must be present')
    end
  end
end

# Shared examples for the `.ensure_link` class method common to all workflow-link join models.
#
# Requires the caller to define:
#   - `workflow`      - a persisted project-scoped Workflow
#   - `artifact`      - the artifact to link (WorkItem, MergeRequest, Ci::Pipeline, Note, etc.)
#   - `link_type`     - the link type symbol (e.g. :source, :created)
#   - `artifact_attr` - the association name on the link model as a symbol
#                       (e.g. :work_item, :merge_request, :pipeline, :note)
RSpec.shared_examples 'a duo workflow link model with ensure_link' do
  subject(:errors) { described_class.ensure_link(workflow: workflow, artifact: artifact, link_type: link_type) }

  it 'creates a link carrying the workflow project and namespace and reports no errors' do
    expect { errors }.to change { described_class.count }.by(1)
    expect(errors).to be_empty

    expect(described_class.last).to have_attributes(
      { workflow: workflow, artifact_attr => artifact,
        project_id: workflow.project_id, namespace_id: workflow.namespace_id,
        link_type: link_type.to_s }
    )
  end

  context 'when the link is invalid' do
    before do
      # Both project_id and namespace_id present violates the project-xor-namespace rule.
      allow(workflow).to receive(:namespace_id).and_return(workflow.project.project_namespace_id)
    end

    it 'reports errors and creates nothing' do
      expect { errors }.not_to change { described_class.count }
      expect(errors.full_messages).to include('either project_id or namespace_id must be present')
    end
  end

  context 'when a matching link already exists' do
    before do
      described_class.ensure_link(workflow: workflow, artifact: artifact, link_type: link_type)
    end

    it 'reports no errors and creates no duplicate' do
      expect { errors }.not_to change { described_class.count }
      expect(errors).to be_empty
    end
  end
end
