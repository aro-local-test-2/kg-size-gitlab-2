# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionArtifacts::PostgresqlFinder, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:other_group) { create(:group) }
  let_it_be(:other_project) { create(:project, group: other_group) }
  let_it_be(:user1) { create(:user) }
  let_it_be(:user2) { create(:user) }
  let_it_be(:workflow1) { create(:duo_workflows_workflow, project: project, user: user1) }
  let_it_be(:workflow2) { create(:duo_workflows_workflow, project: subgroup_project, user: user2) }
  let_it_be(:workflow_outside) { create(:duo_workflows_workflow, project: other_project) }

  # Fixed reference point so that relative timestamps used in artifact creation
  # and in filter parameters are consistent across `let_it_be` (before(:all))
  # and per-example evaluation, avoiding boundary-condition flakiness.
  let_it_be(:reference_time) { Time.current }

  let_it_be(:artifact1) do
    create(:duo_workflow_session_artifact,
      workflow: workflow1,
      workflow_definition: 'software_development',
      workflow_updated_at: reference_time - 2.hours,
      workflow_created_at: reference_time - 3.days)
  end

  let_it_be(:artifact2) do
    create(:duo_workflow_session_artifact,
      workflow: workflow2,
      workflow_definition: 'chat',
      workflow_updated_at: reference_time - 1.hour,
      workflow_created_at: reference_time - 1.day)
  end

  let_it_be(:artifact_outside) do
    create(:duo_workflow_session_artifact, workflow: workflow_outside)
  end

  # Namespace-scoped (project_id: nil) session living on a SUBGROUP. The
  # `in_namespace` scope now walks `self_and_descendants`, so this must surface
  # when the finder is called with the ancestor group as the namespace.
  let_it_be(:subgroup_namespace_workflow) do
    create(:duo_workflows_workflow, :agentic_chat, project: nil, namespace: subgroup, user: create(:user))
  end

  let_it_be(:subgroup_namespace_artifact) do
    create(:duo_workflow_session_artifact, :with_namespace,
      workflow: subgroup_namespace_workflow,
      namespace: subgroup,
      workflow_definition: 'agentic_chat',
      workflow_updated_at: reference_time - 30.minutes,
      workflow_created_at: reference_time - 2.days)
  end

  subject(:results) { described_class.new(namespace: group, params: {}).execute }

  describe '#execute' do
    it 'returns all artifacts scoped to the namespace and its subgroups' do
      expect(results).to contain_exactly(artifact1, artifact2, subgroup_namespace_artifact)
    end

    it 'returns a namespace-scoped artifact on a subgroup when querying the ancestor group' do
      expect(results).to include(subgroup_namespace_artifact)
    end

    it 'excludes artifacts from outside the namespace' do
      expect(results).not_to include(artifact_outside)
    end

    it 'orders by workflow_updated_at DESC, workflow_id DESC' do
      expect(results.to_a).to eq([subgroup_namespace_artifact, artifact2, artifact1])
    end

    it 'eager loads the project association' do
      expect(results.first.association(:project)).to be_loaded
    end

    it 'returns nothing for a namespace with no artifacts' do
      empty_group = create(:group)

      expect(described_class.new(namespace: empty_group, params: {}).execute).to be_empty
    end

    context 'with namespace-scoped (group-level) artifacts' do
      let_it_be(:group_workflow) { create(:duo_workflows_workflow, project: nil, namespace: group) }
      let_it_be(:group_artifact) do
        create(:duo_workflow_session_artifact, :with_namespace, workflow: group_workflow, namespace: group)
      end

      let_it_be(:subgroup_workflow) { create(:duo_workflows_workflow, project: nil, namespace: subgroup) }
      let_it_be(:subgroup_artifact) do
        create(:duo_workflow_session_artifact, :with_namespace, workflow: subgroup_workflow, namespace: subgroup)
      end

      it 'includes group-level artifacts attached to the namespace itself' do
        expect(results).to include(group_artifact)
      end

      it 'includes group-level artifacts attached to descendant subgroups' do
        expect(results).to include(subgroup_artifact)
      end
    end

    context 'when filtering by a single workflow_id' do
      subject(:results) do
        described_class.new(namespace: group, params: { workflow_id: workflow2.id }).execute
      end

      it 'returns only the artifact for that workflow' do
        expect(results).to contain_exactly(artifact2)
      end
    end

    context 'when filtering by agent_type' do
      let_it_be(:external_workflow) do
        create(:duo_workflows_workflow, :external, project: project, user: create(:user))
      end

      let_it_be(:external_artifact) do
        create(:duo_workflow_session_artifact, workflow: external_workflow, workflow_updated_at: 10.minutes.ago)
      end

      subject(:results) do
        described_class.new(namespace: group, params: { agent_type_filter: agent_type_filter }).execute
      end

      context 'when :none' do
        let(:agent_type_filter) { :none }

        it 'returns only artifacts with a NULL agent_type' do
          expect(results).to contain_exactly(artifact1, artifact2, subgroup_namespace_artifact)
        end
      end

      context 'when :any' do
        let(:agent_type_filter) { :any }

        it 'returns only artifacts with a non-NULL agent_type' do
          expect(results).to contain_exactly(external_artifact)
        end
      end

      context 'when nil' do
        let(:agent_type_filter) { nil }

        it 'returns every artifact in the namespace' do
          expect(results).to contain_exactly(artifact1, artifact2, subgroup_namespace_artifact, external_artifact)
        end
      end
    end

    context 'when filtering by workflow_definition' do
      subject(:results) do
        described_class.new(namespace: group, params: { workflow_definition: 'chat' }).execute
      end

      it 'returns only artifacts with the matching definition' do
        expect(results).to contain_exactly(artifact2)
      end
    end

    context 'when filtering by not: { workflow_definition }' do
      subject(:results) do
        described_class.new(namespace: group, params: { not: { workflow_definition: 'chat' } }).execute
      end

      it 'excludes artifacts with the given definition' do
        expect(results).to contain_exactly(artifact1, subgroup_namespace_artifact)
      end
    end

    context 'when filtering by workflow_created_after' do
      subject(:results) do
        described_class.new(namespace: group, params: { workflow_created_after: reference_time - 2.days }).execute
      end

      it 'returns artifacts created on or after the bound (inclusive)' do
        # artifact1 created 3 days before reference_time (excluded),
        # artifact2 1 day before reference_time (included),
        # subgroup_namespace_artifact 2 days before reference_time (included, boundary is inclusive).
        expect(results).to contain_exactly(artifact2, subgroup_namespace_artifact)
      end
    end

    context 'when filtering by workflow_created_before' do
      subject(:results) do
        described_class.new(namespace: group, params: { workflow_created_before: reference_time - 2.days }).execute
      end

      it 'returns artifacts created on or before the bound (inclusive)' do
        # artifact1 created 3 days before reference_time (included),
        # artifact2 1 day before reference_time (excluded),
        # subgroup_namespace_artifact 2 days before reference_time (included, boundary is inclusive).
        expect(results).to contain_exactly(artifact1, subgroup_namespace_artifact)
      end
    end

    context 'when filtering by both workflow_created_after and workflow_created_before' do
      subject(:results) do
        described_class.new(
          namespace: group,
          params: {
            workflow_created_after: reference_time - 3.days,
            workflow_created_before: reference_time - 36.hours
          }
        ).execute
      end

      it 'returns artifacts within the date range' do
        # artifact1 at 3 days before reference_time (included, lower boundary),
        # artifact2 at 1 day before reference_time (excluded, above upper bound of 36h),
        # subgroup_namespace_artifact at 2 days before reference_time (included, within range).
        expect(results).to contain_exactly(artifact1, subgroup_namespace_artifact)
      end
    end

    context 'when filtering by user_id' do
      subject(:results) do
        described_class.new(namespace: group, params: { user_id: user1.id }).execute
      end

      it 'returns only artifacts triggered by the given user' do
        expect(results).to contain_exactly(artifact1)
      end
    end

    context 'when filtering by not: { user_id }' do
      subject(:results) do
        described_class.new(namespace: group, params: { not: { user_id: user1.id } }).execute
      end

      it 'excludes artifacts triggered by the given user' do
        # subgroup_namespace_artifact has a different user; artifact2 has user2.
        # NULL user_id rows would also be excluded, but all rows here have user_id set.
        expect(results).to contain_exactly(artifact2, subgroup_namespace_artifact)
      end
    end

    context 'when filtering by project_path' do
      subject(:results) do
        described_class.new(namespace: group, params: { project_path: project.full_path }).execute
      end

      it 'returns only artifacts belonging to the given project' do
        expect(results).to contain_exactly(artifact1)
      end

      it 'excludes namespace-scoped (project_id: nil) artifacts' do
        expect(results).not_to include(subgroup_namespace_artifact)
      end

      it 'returns artifacts for a project in a descendant subgroup' do
        results = described_class.new(namespace: group, params: { project_path: subgroup_project.full_path }).execute

        expect(results).to contain_exactly(artifact2)
      end
    end

    # `array_scope` is narrowed to the project's own namespace, chained onto the
    # hierarchy scope. These guard that it remains an intersection with the requested
    # hierarchy rather than replacing it.
    context 'when filtering by project_path for a project outside the namespace hierarchy' do
      subject(:results) do
        described_class.new(namespace: group, params: { project_path: other_project.full_path }).execute
      end

      it 'returns an empty result set' do
        expect(results).to be_empty
      end

      it 'does not return the artifact belonging to that project' do
        expect(results).not_to include(artifact_outside)
      end
    end

    context 'when filtering by project_path that does not resolve' do
      subject(:results) do
        described_class.new(namespace: group, params: { project_path: 'nonexistent/path' }).execute
      end

      it 'returns an empty result set' do
        expect(results).to be_empty
      end
    end

    context 'when resolving project_path' do
      subject(:results) do
        described_class.new(namespace: group, params: { project_path: project.full_path }).execute
      end

      # `array_scope` and the row filter both need the resolved project, so the lookup
      # is memoized to keep it at one query.
      it 'looks the project up once' do
        queries = ActiveRecord::QueryRecorder.new { results.to_a }
        lookups = queries.log.grep(/FROM "projects".*"routes"/m)

        expect(lookups.size).to eq(1)
      end
    end

    context 'when filtering by not: { project_path }' do
      subject(:results) do
        described_class.new(namespace: group, params: { not: { project_path: project.full_path } }).execute
      end

      it 'excludes artifacts belonging to the given project' do
        expect(results).to contain_exactly(artifact2, subgroup_namespace_artifact)
      end

      it 'includes namespace-scoped (project_id: nil) artifacts' do
        expect(results).to include(subgroup_namespace_artifact)
      end

      # A ProjectNamespace is a Namespace, so a namespace-scoped session can live in the
      # excluded project's own namespace. This is why the exclusion filters rows rather
      # than removing that namespace from `array_scope`, which would drop this row.
      it 'includes a project_id: nil artifact living in the excluded project namespace' do
        workflow = create(:duo_workflows_workflow, :agentic_chat,
          project: nil, namespace: project.project_namespace, user: create(:user))
        artifact = create(:duo_workflow_session_artifact, :with_namespace,
          workflow: workflow, namespace: project.project_namespace)

        expect(results).to include(artifact)
      end
    end

    context 'when not: { project_path } does not resolve' do
      subject(:results) do
        described_class.new(namespace: group, params: { not: { project_path: 'nonexistent/path' } }).execute
      end

      it 'returns all namespace results with no exclusion filter applied' do
        expect(results).to contain_exactly(artifact1, artifact2, subgroup_namespace_artifact)
      end
    end

    context 'when combining workflow_definition and user_id filters' do
      subject(:results) do
        described_class.new(
          namespace: group,
          params: { workflow_definition: 'software_development', user_id: user1.id }
        ).execute
      end

      it 'returns only artifacts matching both conditions' do
        expect(results).to contain_exactly(artifact1)
      end
    end

    context 'when combining project_path with other filters' do
      it 'returns only artifacts matching project_path and workflow_definition' do
        results = described_class.new(
          namespace: group,
          params: { project_path: project.full_path, workflow_definition: 'software_development' }
        ).execute

        expect(results).to contain_exactly(artifact1)
      end

      it 'returns nothing when workflow_definition does not match the project_path artifacts' do
        results = described_class.new(
          namespace: group,
          params: { project_path: project.full_path, workflow_definition: 'chat' }
        ).execute

        expect(results).to be_empty
      end

      it 'returns only artifacts matching project_path and user_id' do
        results = described_class.new(
          namespace: group,
          params: { project_path: project.full_path, user_id: user1.id }
        ).execute

        expect(results).to contain_exactly(artifact1)
      end

      it 'returns nothing when user_id does not match the project_path artifacts' do
        results = described_class.new(
          namespace: group,
          params: { project_path: project.full_path, user_id: user2.id }
        ).execute

        expect(results).to be_empty
      end
    end

    context 'when combining agent_type_filter and user_id filters' do
      subject(:results) do
        described_class.new(
          namespace: group,
          params: { agent_type_filter: :none, user_id: user1.id }
        ).execute
      end

      it 'returns only artifacts matching both conditions' do
        expect(results).to contain_exactly(artifact1)
      end
    end
  end
end
