# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion, feature_category: :vulnerability_management do
  describe '.ingest_pipeline?' do
    let_it_be(:project) { create(:project, :repository) }

    subject(:ingest_pipeline?) { described_class.ingest_pipeline?(pipeline) }

    context 'when pipeline is on the default branch' do
      let(:pipeline) { create(:ci_pipeline, project: project, ref: project.default_branch) }

      it { is_expected.to be true }
    end

    context 'when pipeline is a workload matching the default branch HEAD' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123',
          sha: project.commit(project.default_branch).id, source: :duo_workflow)
      end

      it { is_expected.to be true }

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it { is_expected.to be false }
      end
    end

    context 'when pipeline is not on the default branch' do
      let(:pipeline) { create(:ci_pipeline, project: project, ref: 'feature-branch') }

      context 'when the pipeline ref is tracked' do
        before do
          create(:security_project_tracked_context, :tracked,
            project: project,
            context_name: pipeline.ref,
            context_type: :branch)
        end

        it { is_expected.to be true }
      end

      context 'when the pipeline ref is not tracked' do
        it { is_expected.to be false }
      end

      context 'when the pipeline is a tag' do
        let(:pipeline) { create(:ci_pipeline, :tag, project: project, ref: 'v1.0.0') }

        context 'when the tag is tracked' do
          before do
            create(:security_project_tracked_context, :tracked, :tag,
              project: project,
              context_name: pipeline.ref)
          end

          it { is_expected.to be true }
        end

        context 'when the tag is not tracked' do
          it { is_expected.to be false }
        end
      end

      context 'when the pipeline is a merge request pipeline' do
        let_it_be(:merge_request) do
          create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
        end

        let(:pipeline) do
          create(:ci_pipeline, :detached_merge_request_pipeline, project: project, merge_request: merge_request)
        end

        context 'when the source branch is tracked' do
          before do
            create(:security_project_tracked_context, :tracked, project: project, context_name: 'feature')
          end

          it { is_expected.to be true }

          context 'when the feature flag is disabled' do
            before do
              stub_feature_flags(vulnerabilities_across_contexts: false)
            end

            it { is_expected.to be false }
          end
        end

        context 'when the source branch is not tracked' do
          it { is_expected.to be false }
        end
      end

      context 'when the pipeline is a merge request pipeline sourced from the default branch' do
        let_it_be(:merge_request) do
          create(:merge_request,
            source_project: project,
            source_branch: project.default_branch,
            target_branch: 'feature')
        end

        let(:pipeline) do
          create(:ci_pipeline, :detached_merge_request_pipeline, project: project, merge_request: merge_request)
        end

        # The default branch context is always tracked, so without the carve-out this would ingest.
        before do
          create(:security_project_tracked_context, :tracked,
            project: project,
            context_name: project.default_branch,
            is_default: true)
        end

        it { is_expected.to be false }
      end

      context 'when feature flag is disabled' do
        before do
          stub_feature_flags(vulnerabilities_across_contexts: false)
        end

        it { is_expected.to be false }
      end
    end
  end
end
