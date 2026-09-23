# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VisibleApprovable, factory_default: :keep, feature_category: :code_review_workflow do
  let_it_be(:organization) { create_default(:common_organization) }
  let_it_be_with_reload(:project) { create(:project, :small_repo) }
  let_it_be_with_refind(:resource) { create(:merge_request, source_project: project) }

  describe '#overall_approvers' do
    let_it_be_with_refind(:approver) { create(:user) }
    let_it_be_with_refind(:code_owner) { create(:user) }

    let!(:project_regular_rule) { create(:approval_project_rule, project: project, users: [approver]) }
    let!(:code_owner_rule) { create(:code_owner_rule, merge_request: resource, users: [code_owner]) }

    before_all do
      project.add_members([approver, code_owner], :developer)
    end

    subject { resource.overall_approvers }

    it 'returns a list of all the project approvers' do
      is_expected.to contain_exactly(approver, code_owner)
    end

    context 'when exclude_code_owners is true' do
      subject { resource.overall_approvers(exclude_code_owners: true) }

      it 'excludes code owners' do
        is_expected.to contain_exactly(approver)
      end
    end

    context 'when approvers are overwritten' do
      let!(:merge_request_regular_rule) { create(:approval_merge_request_rule, merge_request: resource, users: [create(:user)]) }

      it 'returns the list of all the merge request level approvers' do
        is_expected.to contain_exactly(*merge_request_regular_rule.users, code_owner)
      end
    end

    context 'when author is an approver' do
      let_it_be_with_refind(:approver) { resource.author }

      before_all do
        project.add_developer(approver)
      end

      it 'includes author regardless of project setting because filtering happens at rule level' do
        project.update!(merge_requests_author_approval: false)
        mr = resource.class.find(resource.id)

        expect(mr.overall_approvers).to include(approver)
      end

      it 'includes author if author is able to approve' do
        project.update!(merge_requests_author_approval: true)
        mr = resource.class.find(resource.id)

        expect(mr.overall_approvers).to include(approver)
      end
    end

    context 'when a committer is an approver' do
      let_it_be_with_reload(:project) { create(:project, :repository, developers: [code_owner]) }
      let_it_be_with_refind(:resource) { create(:merge_request, source_project: project) }
      let_it_be_with_refind(:approver) { create(:user, email: resource.commits.without_merge_commits.first.committer_email) }

      before_all do
        project.add_developer(approver)
      end

      it 'includes committer regardless of project setting because filtering happens at rule level' do
        project.update!(merge_requests_disable_committers_approval: true)

        is_expected.to include(approver)
      end

      it 'includes the committer if committers are able to approve' do
        project.update!(merge_requests_disable_committers_approval: false)

        is_expected.to include(approver)
      end
    end
  end

  describe '#reset_approval_cache!' do
    let_it_be_with_refind(:resource) { create(:merge_request, source_project: project, source_branch: 'reset-approval-cache-test') }

    it 'clears overall approver ID memoization', :aggregate_failures do
      approver = create(:user)

      approval_state = resource.approval_state

      expect(approval_state.overall_approver_ids).to be_empty

      create(:approval, merge_request: resource, user: approver)

      expect { resource.reset_approval_cache! }
        .to change { resource.approval_state.overall_approver_ids }
        .from(Set.new)
        .to(Set[approver.id])

      expect(resource.approval_state).not_to be(approval_state)
    end

    it 'deletes the approval mergeability cache', :clean_gitlab_redis_cache do
      check = MergeRequests::Mergeability::CheckApprovedService.new(merge_request: resource, params: {})
      cache_key = "#{check.cache_key}:#{Gitlab::MergeRequests::Mergeability::RedisInterface::VERSION}"

      Gitlab::Redis::Cache.with { |redis| redis.set(cache_key, '{"status":"success"}', ex: 30) }
      expect(Gitlab::Redis::Cache.with { |redis| redis.exists?(cache_key) }).to be true

      resource.reset_approval_cache!

      expect(Gitlab::Redis::Cache.with { |redis| redis.exists?(cache_key) }).to be false
    end
  end

  describe '#authors_can_approve?' do
    subject { resource.authors_can_approve? }

    it 'returns false when merge_requests_author_approval flag is off' do
      is_expected.to be_falsey
    end

    it 'returns true when merge_requests_author_approval flag is turned on' do
      project.update!(merge_requests_author_approval: true)

      is_expected.to be_truthy
    end
  end
end
