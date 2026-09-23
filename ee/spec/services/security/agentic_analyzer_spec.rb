# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AgenticAnalyzer, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :repository) }

  describe '.default_branch_scan?' do
    subject(:default_branch_scan?) { described_class.default_branch_scan?(pipeline) }

    let(:default_sha) { project.commit(project.default_branch).id }

    context 'when pipeline is a workload with SHA matching default branch HEAD' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: default_sha, source: :duo_workflow)
      end

      it { is_expected.to be true }
    end

    context 'when pipeline is not a workload' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'feature-branch', sha: default_sha)
      end

      it { is_expected.to be false }
    end

    context 'when the feature flag is disabled' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: default_sha, source: :duo_workflow)
      end

      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it { is_expected.to be false }
    end

    context 'when pipeline SHA does not match default branch HEAD' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: 'f' * 40, source: :duo_workflow)
      end

      it { is_expected.to be false }
    end

    context 'when the project has no commits' do
      let_it_be(:empty_project) { create(:project) }

      let(:pipeline) do
        create(:ci_pipeline, project: empty_project, ref: 'refs/workloads/abc123', sha: 'a' * 40, source: :duo_workflow)
      end

      it { is_expected.to be false }
    end

    context 'when called multiple times for the same pipeline' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: default_sha, source: :duo_workflow)
      end

      it 'memoizes the result to avoid duplicate Gitaly calls' do
        allow(pipeline).to receive(:project).and_return(project)

        expect(project).to receive(:commit).once.and_call_original

        Gitlab::SafeRequestStore.ensure_request_store do
          2.times { described_class.default_branch_scan?(pipeline) }
        end
      end
    end
  end
end
