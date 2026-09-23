# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::ResourceContextBuilder, feature_category: :duo_agent_platform do
  include ProjectForksHelper

  let(:schema_path) do
    Rails.root.join('app/validators/json_schemas/agent_platform/agent_platform_resource_context/1.1.0.json')
  end

  let(:schema) { JSONSchemer.schema(schema_path) }

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }

  subject(:fields) { described_class.build(resource) }

  shared_examples 'a schema-conformant resource context' do
    it 'is valid against the agent_platform_resource_context schema' do
      expect(schema.valid?(fields)).to be(true), schema.validate(fields).to_a.inspect
    end
  end

  context 'when resource is nil' do
    let(:resource) { nil }

    it { is_expected.to be_nil }
  end

  context 'when resource is an unsupported type' do
    let(:resource) { create(:user) }

    it { is_expected.to be_nil }
  end

  context 'when resource is a Ci::Pipeline' do
    let(:resource) { create(:ci_pipeline, project: project, ref: 'feature-branch') }

    include_examples 'a schema-conformant resource context'

    it 'carries the pipeline as the primary target and no merge request' do
      expect(fields).to include(
        "resource_type" => "pipeline",
        "resource_id" => resource.to_global_id.to_s,
        "resource_web_url" => Gitlab::UrlBuilder.build(resource),
        "pipeline_id" => resource.to_global_id.to_s,
        "pipeline_web_url" => Gitlab::UrlBuilder.build(resource),
        "pipeline_source_branch" => "feature-branch",
        "merge_request_id" => "",
        "merge_request_diff_sha" => "",
        "merge_request_web_url" => "",
        "work_item_id" => "",
        "work_item_web_url" => ""
      )
    end

    context 'with an associated merge request' do
      let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project) }
      let(:resource) { create(:ci_pipeline, :detached_merge_request_pipeline, merge_request: merge_request) }

      include_examples 'a schema-conformant resource context'

      it 'carries the merge request' do
        expect(fields).to include(
          "merge_request_id" => merge_request.iid.to_s,
          "merge_request_diff_sha" => merge_request.diff_head_sha,
          "merge_request_web_url" => Gitlab::UrlBuilder.build(merge_request)
        )
      end
    end

    context 'with an open merge request from a fork' do
      let_it_be(:fork) { fork_project(project, nil, repository: true) }
      let_it_be_with_reload(:merge_request) do
        create(:merge_request, source_project: fork, target_project: project)
      end

      let(:resource) do
        create(:ci_pipeline, project: fork, ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      end

      include_examples 'a schema-conformant resource context'

      it 'carries the merge request with an IID scoped to the upstream (target) project, not the fork' do
        # MergeRequest#project is aliased to target_project, and iid is scoped to it (merge_request.rb).
        # The pipeline runs in the fork, so merge_request_id here is not scoped to resource.project;
        # merge_request_web_url is unambiguous regardless (see the schema's merge_request_id description).
        expect(merge_request.project).to eq(project)
        expect(fields).to include(
          "merge_request_id" => merge_request.iid.to_s,
          "merge_request_web_url" => Gitlab::UrlBuilder.build(merge_request)
        )
      end
    end

    context 'when merge_request is pre-resolved by the caller' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }

      subject(:fields) { described_class.build(resource, merge_request: merge_request) }

      it 'uses the given merge request instead of querying for it' do
        expect(resource).not_to receive(:all_merge_requests_by_recency)

        expect(fields).to include(
          "merge_request_id" => merge_request.iid.to_s,
          "merge_request_web_url" => Gitlab::UrlBuilder.build(merge_request)
        )
      end
    end

    context 'when the caller resolved no merge request' do
      subject(:fields) { described_class.build(resource, merge_request: nil) }

      it 'does not query for one and carries an empty merge request' do
        expect(resource).not_to receive(:all_merge_requests_by_recency)

        expect(fields).to include("merge_request_id" => "", "merge_request_web_url" => "")
      end
    end
  end

  context 'when resource is a MergeRequest' do
    let(:resource) { create(:merge_request, source_project: project) }

    include_examples 'a schema-conformant resource context'

    it 'carries the merge request as the primary target and no pipeline' do
      expect(fields).to include(
        "resource_type" => "merge_request",
        "resource_id" => resource.iid.to_s,
        "resource_web_url" => Gitlab::UrlBuilder.build(resource),
        "pipeline_id" => "",
        "pipeline_web_url" => "",
        "pipeline_source_branch" => "",
        "merge_request_id" => resource.iid.to_s,
        "merge_request_diff_sha" => resource.diff_head_sha,
        "merge_request_web_url" => Gitlab::UrlBuilder.build(resource),
        "work_item_id" => "",
        "work_item_web_url" => ""
      )
    end

    context 'with a head pipeline matching the current diff head' do
      let_it_be_with_reload(:resource) { create(:merge_request, source_project: project) }
      let_it_be(:pipeline) do
        create(:ci_pipeline, project: project, sha: resource.diff_head_sha, head_pipeline_of: resource)
      end

      include_examples 'a schema-conformant resource context'

      it 'carries the pipeline' do
        expect(fields).to include(
          "pipeline_id" => pipeline.to_global_id.to_s,
          "pipeline_web_url" => Gitlab::UrlBuilder.build(pipeline),
          "pipeline_source_branch" => pipeline.source_ref
        )
      end
    end
  end

  context 'when resource is an Issue' do
    let(:resource) { create(:issue, project: project) }

    include_examples 'a schema-conformant resource context'

    it 'carries the issue as the primary target and as a work_item' do
      expect(fields).to eq(
        "resource_type" => "work_item",
        "resource_id" => resource.iid.to_s,
        "resource_web_url" => Gitlab::UrlBuilder.build(resource),
        "pipeline_id" => "",
        "pipeline_web_url" => "",
        "pipeline_source_branch" => "",
        "merge_request_id" => "",
        "merge_request_diff_sha" => "",
        "merge_request_web_url" => "",
        "work_item_id" => resource.iid.to_s,
        "work_item_web_url" => Gitlab::UrlBuilder.build(resource)
      )
    end
  end

  context 'when resource is a WorkItem' do
    let(:resource) { create(:work_item, :task, project: project) }

    include_examples 'a schema-conformant resource context'

    it 'is handled via the Issue branch (WorkItem < Issue)' do
      expect(fields["resource_type"]).to eq("work_item")
    end
  end

  context 'when resource is a Vulnerability' do
    let(:resource) { create(:vulnerability, project: project) }

    include_examples 'a schema-conformant resource context'

    it 'carries the vulnerability as the primary target with all type-prefixed fields empty' do
      expect(fields).to eq(
        "resource_type" => "vulnerability",
        "resource_id" => resource.to_global_id.to_s,
        "resource_web_url" => Gitlab::UrlBuilder.build(resource),
        "pipeline_id" => "",
        "pipeline_web_url" => "",
        "pipeline_source_branch" => "",
        "merge_request_id" => "",
        "merge_request_diff_sha" => "",
        "merge_request_web_url" => "",
        "work_item_id" => "",
        "work_item_web_url" => ""
      )
    end
  end
end
