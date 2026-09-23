# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ai::DuoWorkflows::Tools::RiskClassification::Results, :with_current_organization,
  feature_category: :duo_code_review do
  let_it_be(:foundational_flow) { Ai::Catalog::FoundationalFlow.risk_classification_v1 }
  let_it_be(:organization) { create(:common_organization) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }
  let_it_be(:oauth_app) { create(:doorkeeper_application) }
  let_it_be(:scopes) { ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{user.id}"] }
  let_it_be(:service_account) do
    create(:user, :service_account,
      composite_identity_enforced: true,
      organization: organization,
      provisioned_by_group: group
    )
  end

  let_it_be(:catalog_item) do
    create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'risk_classification/v1')
  end

  let_it_be(:parent_item_consumer) do
    create(:ai_catalog_item_consumer, item: catalog_item, group: group, service_account: service_account)
  end

  let_it_be(:child_item_consumer) do
    create(:ai_catalog_item_consumer, item: catalog_item, project: project, parent_item_consumer: parent_item_consumer)
  end

  let_it_be(:token) do
    create(:oauth_access_token,
      organization: organization,
      application: oauth_app,
      resource_owner: service_account,
      expires_in: 1.hour,
      scopes: scopes
    )
  end

  before_all do
    group.add_developer(user)
    project.add_developer(service_account)
  end

  before do
    stub_licensed_features(ai_features: true)
    # The flow's own enablement path gates on the project's root namespace, not
    # the project itself, so the flag must be stubbed for the group here too.
    stub_feature_flags(duo_mr_risk_classification: group)
    # Clear memoization to prevent state leakage from other specs that may have
    # called catalog_item before ai_catalog_items records were created
    foundational_flow.clear_memoization(:catalog_item)
  end

  describe 'POST /ai/duo_workflows/tools/risk_classification/results' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let_it_be(:workflow) do
      create(
        :duo_workflows_workflow,
        project: project,
        user: user,
        merge_request: merge_request,
        workflow_definition: 'risk_classification/v1'
      )
    end

    let(:path) { '/ai/duo_workflows/tools/risk_classification/results' }
    let(:claims) do
      [
        { name: 'authorization', value: 'true', evidence: 'app/policies/project_policy.rb:44' },
        { name: 'api_contract', value: 'false' }
      ]
    end

    let(:params) do
      {
        project_id: project.id,
        merge_request_iid: merge_request.iid,
        diff_sha: merge_request.diff_head_sha,
        workflow_id: workflow.id,
        claims: claims,
        summary: 'Adds a session token refresh path.'
      }
    end

    context 'when successful' do
      it 'queues the assessment for scoring and returns no content' do
        expected_classification = {
          'claims' => {
            'authorization' => { 'value' => 'true', 'evidence' => 'app/policies/project_policy.rb:44' },
            'api_contract' => { 'value' => 'false' }
          },
          'summary' => 'Adds a session token refresh path.'
        }

        expect_next_instance_of(MergeRequests::RiskAssessment) do |assessment|
          expect(assessment).to receive(:enqueue_risk_score_calculation)
            .with(merge_request.diff_head_sha, expected_classification, workflow.id)
        end

        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:no_content)
        expect(response.body).to be_empty

        assessment = merge_request.reload.risk_assessment
        expect(assessment).to be_queued
        expect(assessment.diff_sha).to eq(merge_request.diff_head_sha)
      end

      context 'without a summary' do
        let(:params) do
          { project_id: project.id, merge_request_iid: merge_request.iid,
            diff_sha: merge_request.diff_head_sha, workflow_id: workflow.id, claims: claims }
        end

        it 'returns no content' do
          post api(path, user, oauth_access_token: token), params: params

          expect(response).to have_gitlab_http_status(:no_content)
        end
      end
    end

    describe 'claim and summary bounds' do
      subject(:submit) { post api(path, user, oauth_access_token: token), params: params }

      shared_examples 'a rejected payload' do
        it 'returns bad request without persisting an assessment' do
          submit

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(merge_request.reload.risk_assessment).to be_nil
        end
      end

      context 'when a claim name exceeds 64 characters' do
        let(:claims) { [{ name: 'a' * 65, value: 'true' }] }

        it_behaves_like 'a rejected payload'
      end

      context 'when a claim value exceeds 256 characters' do
        let(:claims) { [{ name: 'authorization', value: 'v' * 257 }] }

        it_behaves_like 'a rejected payload'
      end

      context 'when claim evidence exceeds 256 characters' do
        let(:claims) { [{ name: 'authorization', value: 'true', evidence: 'e' * 257 }] }

        it_behaves_like 'a rejected payload'
      end

      context 'when the summary exceeds 2048 characters' do
        let(:params) do
          { project_id: project.id, merge_request_iid: merge_request.iid,
            diff_sha: merge_request.diff_head_sha, workflow_id: workflow.id, claims: claims,
            summary: 's' * 2049 }
        end

        it_behaves_like 'a rejected payload'
      end

      context 'when there are more than 1000 claims' do
        let(:claims) { Array.new(1001) { |i| { name: "claim_#{i}", value: 'true' } } }

        it_behaves_like 'a rejected payload'
      end

      context 'when a claim name is not snake_case' do
        let(:claims) { [{ name: 'TouchesAuth', value: 'true' }] }

        it_behaves_like 'a rejected payload'
      end

      context 'when a claim name is an empty string' do
        let(:claims) { [{ name: '', value: 'true' }] }

        it_behaves_like 'a rejected payload'
      end

      # A nil name used to slip past both `requires` and the regexp validator and land
      # in the jsonb under an empty key.
      context 'when a claim name is null' do
        let(:claims) { [{ name: nil, value: 'true' }] }

        it_behaves_like 'a rejected payload'
      end

      context 'when a claim value is null' do
        let(:claims) { [{ name: 'authorization', value: nil }] }

        it_behaves_like 'a rejected payload'
      end

      # Each claim is individually within bounds, but the envelope is not.
      context 'when the claims are individually valid but exceed the column size limit' do
        let(:claims) do
          Array.new(1000) { |i| { name: "c#{i}#{'x' * 55}", value: 'v' * 256, evidence: 'e' * 256 } }
        end

        it 'returns bad request naming the limit' do
          submit

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include(
            "exceeds the maximum of #{MergeRequests::RiskAssessment::SCHEMA_SIZE_LIMIT} bytes"
          )
          expect(merge_request.reload.risk_assessment).to be_nil
        end
      end
    end

    context 'when project_id is missing' do
      let(:params) do
        { merge_request_iid: merge_request.iid, diff_sha: merge_request.diff_head_sha, workflow_id: workflow.id,
          claims: claims }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when merge_request_iid is missing' do
      let(:params) do
        { project_id: project.id, diff_sha: merge_request.diff_head_sha, workflow_id: workflow.id, claims: claims }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when workflow_id is missing' do
      let(:params) do
        { project_id: project.id, merge_request_iid: merge_request.iid,
          diff_sha: merge_request.diff_head_sha, claims: claims }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when diff_sha is missing' do
      let(:params) do
        { project_id: project.id, merge_request_iid: merge_request.iid, workflow_id: workflow.id, claims: claims }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when diff_sha is not a full 40-character sha' do
      let(:params) do
        { project_id: project.id, merge_request_iid: merge_request.iid, diff_sha: 'abc123', workflow_id: workflow.id,
          claims: claims }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when claims is missing' do
      let(:params) do
        { project_id: project.id, merge_request_iid: merge_request.iid, diff_sha: merge_request.diff_head_sha,
          workflow_id: workflow.id }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when a claim is missing a value' do
      let(:params) do
        { project_id: project.id, merge_request_iid: merge_request.iid, diff_sha: merge_request.diff_head_sha,
          claims: [{ name: 'authorization' }] }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when claims contains a duplicate name' do
      let(:params) do
        { project_id: project.id, merge_request_iid: merge_request.iid, diff_sha: merge_request.diff_head_sha,
          claims: [{ name: 'authorization', value: 'true' }, { name: 'authorization', value: 'false' }] }
      end

      it 'returns bad request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when project is not found' do
      let(:params) do
        { project_id: non_existing_record_id, merge_request_iid: merge_request.iid,
          diff_sha: merge_request.diff_head_sha, workflow_id: workflow.id, claims: claims }
      end

      it 'returns not found' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when merge request is not found' do
      let(:params) do
        { project_id: project.id, merge_request_iid: non_existing_record_id,
          diff_sha: merge_request.diff_head_sha, workflow_id: workflow.id, claims: claims }
      end

      it 'returns not found' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when user is not authenticated' do
      it 'returns unauthorized' do
        post api(path), params: params

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when called without composite identity' do
      it 'returns forbidden' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq(
          '403 Forbidden - This endpoint can only be accessed by Duo Workflow Service'
        )
      end
    end

    context 'when service account does not match the resolved flow service account' do
      let_it_be(:mismatched_service_account) do
        create(:user, :service_account, organization: organization)
      end

      let_it_be(:mismatched_token) do
        create(:oauth_access_token,
          organization: organization,
          application: oauth_app,
          resource_owner: mismatched_service_account,
          expires_in: 1.hour,
          scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{user.id}"]
        )
      end

      before_all do
        project.add_developer(mismatched_service_account)
      end

      it 'returns forbidden' do
        post api(path, user, oauth_access_token: mismatched_token), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq(
          '403 Forbidden - This endpoint can only be accessed by Duo Workflow Service'
        )
      end
    end

    context 'when the flow is not registered for the project' do
      let_it_be(:unregistered_service_account) do
        create(:user, :service_account, composite_identity_enforced: true, organization: organization)
      end

      let_it_be(:unregistered_token) do
        create(:oauth_access_token,
          organization: organization,
          application: oauth_app,
          resource_owner: unregistered_service_account,
          expires_in: 1.hour,
          scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{user.id}"]
        )
      end

      before_all do
        project.add_developer(unregistered_service_account)
      end

      it 'returns forbidden' do
        post api(path, user, oauth_access_token: unregistered_token), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq(
          '403 Forbidden - This endpoint can only be accessed by Duo Workflow Service'
        )
      end
    end

    context 'when service account matches the resolved flow service account' do
      it 'processes the request' do
        post api(path, user, oauth_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:no_content)
      end
    end
  end
end
