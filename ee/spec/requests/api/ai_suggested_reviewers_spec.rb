# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::AiSuggestedReviewers, feature_category: :code_review_workflow do
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:guest) { create(:user) }
  let_it_be(:reviewer_a) { create(:user) }
  let_it_be(:reviewer_b) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group, creator: maintainer) }
  let_it_be(:merge_request) { create(:merge_request, author: maintainer, source_project: project) }
  let_it_be(:catalog_item) do
    create(:ai_catalog_item, :flow, :with_foundational_flow_reference,
      foundational_flow_reference: 'recommend_reviewers/v1')
  end

  let_it_be(:foundational_flow) { ::Ai::Catalog::FoundationalFlow.recommend_reviewers_v1 }

  let_it_be(:service_account) do
    create(:user, :service_account, composite_identity_enforced: true, provisioned_by_group: group)
  end

  let_it_be(:item_consumer) do
    create(:ai_catalog_item_consumer, item: catalog_item, group: group, service_account: service_account)
  end

  let_it_be(:oauth_app) { create(:doorkeeper_application) }
  let_it_be(:flow_token) do
    create(:oauth_access_token,
      application: oauth_app,
      resource_owner: service_account,
      scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{maintainer.id}"]
    )
  end

  let(:base_url) { "/projects/#{project.id}/merge_requests/#{merge_request.iid}/suggested_reviewers" }

  before_all do
    project.add_maintainer(maintainer)
    project.add_guest(guest)
    project.add_developer(service_account)
  end

  before do
    project.project_setting.update!(duo_foundational_flows_enabled: true)
    create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: catalog_item)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    # FoundationalFlow[] returns a process-wide instance that memoizes catalog_item,
    # so another spec can leave a rolled-back record cached here.
    foundational_flow.clear_memoization(:catalog_item)
  end

  describe 'POST /projects/:id/merge_requests/:merge_request_iid/suggested_reviewers' do
    let(:suggestions) do
      [
        { user_id: reviewer_a.id, reason: 'Owns the changed files.' },
        { user_id: reviewer_b.id, reason: 'Reviewed similar code.' }
      ]
    end

    subject(:post_suggestions) do
      post api(base_url, maintainer, oauth_access_token: flow_token), params: { suggestions: suggestions }
    end

    context 'when the caller is not the flow service account' do
      it 'responds with 403' do
        post api(base_url, maintainer), params: { suggestions: suggestions }

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    it 'persists the suggestions and returns them' do
      post_suggestions

      expect(response).to have_gitlab_http_status(:created)
      expect(json_response.map { |r| r['user']['id'] }).to match_array([reviewer_a.id, reviewer_b.id])
      expect(merge_request.ai_suggested_reviewers.reset.count).to eq(2)
    end

    it 'replaces any previously persisted suggestions' do
      create(:ai_suggested_reviewer, merge_request: merge_request, project: project, user: reviewer_a)

      post_suggestions

      expect(merge_request.ai_suggested_reviewers.reset.pluck(:user_id)).to match_array([reviewer_a.id, reviewer_b.id])
    end

    context 'when a suggested user is already a reviewer' do
      let_it_be(:reviewer_assignment) do
        merge_request.merge_request_reviewers.create!(reviewer: reviewer_b, project: project)
      end

      it 'persists the suggestion but omits that user from the response' do
        post_suggestions

        expect(json_response.map { |r| r['user']['id'] }).to contain_exactly(reviewer_a.id)
        expect(merge_request.ai_suggested_reviewers.reset.pluck(:user_id)).to match_array([reviewer_a.id,
          reviewer_b.id])
      end
    end

    context 'when the rate limit is exceeded' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_return(true)
      end

      it 'responds with 429' do
        post_suggestions

        expect(response).to have_gitlab_http_status(:too_many_requests)
      end
    end

    context 'when the user the flow acts for cannot update the merge request' do
      let_it_be(:guest_flow_token) do
        create(:oauth_access_token,
          application: oauth_app,
          resource_owner: service_account,
          scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{guest.id}"]
        )
      end

      it 'responds with 403' do
        post api(base_url, guest, oauth_access_token: guest_flow_token), params: { suggestions: suggestions }

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'responds with 401' do
        post api(base_url), params: { suggestions: suggestions }

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when suggestions exceeds the maximum size' do
      let(:suggestions) { Array.new(described_class::MAX_SUGGESTIONS + 1) { { user_id: reviewer_a.id } } }

      it 'responds with 400' do
        post_suggestions

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when a suggestion is invalid' do
      let(:suggestions) { [{ user_id: reviewer_a.id, reason: 'a' * (described_class::REASON_LIMIT + 1) }] }

      it 'responds with 400 and persists nothing' do
        post_suggestions

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(merge_request.ai_suggested_reviewers.reset).to be_empty
      end
    end

    context 'when the payload contains a duplicate user' do
      let(:suggestions) { [{ user_id: reviewer_a.id }, { user_id: reviewer_a.id }] }

      it 'persists the user once' do
        post_suggestions

        expect(response).to have_gitlab_http_status(:created)
        expect(merge_request.ai_suggested_reviewers.reset.pluck(:user_id)).to eq([reviewer_a.id])
      end
    end

    context 'when the flow is not available for the project' do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(false)
      end

      it 'responds with 404' do
        post_suggestions

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when a suggestion references an approval rule' do
      let_it_be(:approval_project_rule) { create(:approval_project_rule, project: project) }
      let_it_be(:code_owner_rule) { create(:code_owner_rule, merge_request: merge_request, section: 'Backend') }

      before do
        stub_licensed_features(merge_request_approvers: true, code_owners: true)
      end

      context 'with a merge request rule id and type' do
        let(:suggestions) do
          [{ user_id: reviewer_a.id, approval_rule_id: code_owner_rule.id, approval_rule_type: 'merge_request_rule' }]
        end

        it 'persists the approval merge request rule association and exposes the rule' do
          post_suggestions

          record = merge_request.ai_suggested_reviewers.reset.find_by(user_id: reviewer_a.id)
          expect(record.approval_merge_request_rule_id).to eq(code_owner_rule.id)
          expect(record.approval_project_rule_id).to be_nil
          expect(json_response.first['approval_rule']).to eq(
            { 'id' => code_owner_rule.id, 'name' => code_owner_rule.name, 'section' => 'Backend' }
          )
        end
      end

      context 'with a rule the merge request does not have' do
        let_it_be(:other_project_rule) { create(:approval_project_rule) }

        let(:suggestions) do
          [
            { user_id: reviewer_a.id, approval_rule_id: other_project_rule.id, approval_rule_type: 'project_rule' },
            { user_id: reviewer_b.id, reason: 'Owns the changed files.' }
          ]
        end

        it 'keeps every suggestion and omits the unresolvable rule' do
          post_suggestions

          expect(response).to have_gitlab_http_status(:created)
          expect(merge_request.ai_suggested_reviewers.reset.map(&:user_id))
            .to contain_exactly(reviewer_a.id, reviewer_b.id)
          expect(json_response.map { |entry| entry['approval_rule'] }).to all(be_nil)
        end
      end

      it 'does not query per suggestion when serializing approval rules' do
        # A rule per suggestion: sharing one rule lets the query cache hide a
        # missing preload, because skip_cached drops the repeated lookups.
        rules = %w[Backend Frontend Database].map do |section|
          create(:code_owner_rule, merge_request: merge_request, section: section)
        end

        post_for = ->(users) do
          post api(base_url, maintainer, oauth_access_token: flow_token), params: {
            suggestions: users.each_with_index.map do |user, index|
              { user_id: user.id, approval_rule_id: rules[index].id,
                approval_rule_type: 'merge_request_rule' }
            end
          }
        end

        control = ActiveRecord::QueryRecorder.new { post_for.call([reviewer_a]) }

        expect { post_for.call([reviewer_a, reviewer_b, guest]) }.not_to exceed_query_limit(control)
      end

      context 'with a rule id but no type' do
        let(:suggestions) { [{ user_id: reviewer_a.id, approval_rule_id: approval_project_rule.id }] }

        it 'responds with 400 and persists nothing' do
          post_suggestions

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(merge_request.ai_suggested_reviewers.reset).to be_empty
        end
      end

      context 'with a project rule id and type' do
        let(:suggestions) do
          [{ user_id: reviewer_a.id, approval_rule_id: approval_project_rule.id, approval_rule_type: 'project_rule' }]
        end

        it 'persists the approval project rule association' do
          post_suggestions

          record = merge_request.ai_suggested_reviewers.reset.find_by(user_id: reviewer_a.id)
          expect(record.approval_project_rule_id).to eq(approval_project_rule.id)
          expect(record.approval_merge_request_rule_id).to be_nil
        end
      end
    end
  end
end
