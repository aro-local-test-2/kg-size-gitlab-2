# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ci::JobArtifacts, feature_category: :job_artifacts do
  include HttpBasicAuthHelpers
  include DependencyProxyHelpers
  include Ci::JobTokenScopeHelpers
  include HttpIOHelpers

  let_it_be_with_reload(:project) do
    create(:project, :repository, :in_group, public_builds: false)
  end

  let_it_be_with_reload(:pipeline) do
    create(:ci_pipeline, project: project, sha: project.commit.id, ref: project.default_branch)
  end

  let(:user) { create(:user) }
  let(:api_user) { user }
  let(:guest) { create(:project_member, :guest, project: project).user }
  let!(:job) { create(:ci_build, :artifacts, pipeline: pipeline, project: project) }

  before do
    project.add_developer(user)
  end

  describe 'GET /projects/:id/jobs/:job_id/artifacts' do
    context 'with job artifacts' do
      let(:job) { create(:ci_build, :artifacts, pipeline: pipeline, project: project) }

      subject(:request_artifact) { get api("/projects/#{project.id}/jobs/#{job.id}/artifacts", api_user) }

      context 'with missing artifacts file', :aggregate_failures do
        let(:job_without_artifacts) { create(:ci_build, pipeline: pipeline, project: project) }

        it 'returns not_found and does not audit' do
          expect(::Ci::ArtifactDownloadAuditor).not_to receive(:new)

          get api("/projects/#{project.id}/jobs/#{job_without_artifacts.id}/artifacts", api_user)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'with audit events enabled', :aggregate_failures do
        before do
          create(:audit_events_group_external_streaming_destination, group: project.group.root_ancestor)
          stub_licensed_features(admin_audit_log: true, extended_audit_events: true, external_audit_events: true)
        end

        it 'audits downloads' do
          expect(::Gitlab::Audit::Auditor).to(
            receive(:audit).with(hash_including(name: 'job_artifact_downloaded')).and_call_original
          )

          request_artifact
        end

        it 'audits the requested artifact rather than the archive' do
          artifact = create(:ci_job_artifact, :junit, job: job)

          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(additional_details: hash_including(artifact_id: artifact.id))
          ).and_call_original

          get api("/projects/#{project.id}/jobs/#{job.id}/artifacts", api_user), params: { file_type: 'junit' }
        end
      end

      context 'when the job has both a performance and a browser performance report' do
        # The two reports share a report group, so only the file distinguishes
        # them in the response.
        let!(:performance) do
          create(:ci_job_artifact, job: job, project: project, file_type: :performance, file_format: :raw,
            file: fixture_file_upload('spec/fixtures/trace/sample_trace', 'text/plain'))
        end

        let!(:browser_performance) do
          create(:ci_job_artifact, job: job, project: project, file_type: :browser_performance, file_format: :raw,
            file: fixture_file_upload('spec/fixtures/trace/trace_with_sections', 'text/plain'))
        end

        it 'serves the requested report', :aggregate_failures do
          get api("/projects/#{project.id}/jobs/#{job.id}/artifacts", api_user), params: { file_type: 'performance' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.header['Content-Disposition']).to include(performance.file.filename)

          get api("/projects/#{project.id}/jobs/#{job.id}/artifacts", api_user),
            params: { file_type: 'browser_performance' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.header['Content-Disposition']).to include(browser_performance.file.filename)
        end
      end
    end
  end
end
