# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AutoMergeService, feature_category: :code_review_workflow do
  let_it_be_with_reload(:project) { create(:project, :repository) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let(:service) { described_class.new(project, user) }

  describe '.all_strategies_ordered_by_preference' do
    subject { described_class.all_strategies_ordered_by_preference }

    it 'returns all strategies in preference order' do
      is_expected.to contain_exactly(AutoMergeService::STRATEGY_MERGE_TRAIN,
        AutoMergeService::STRATEGY_ADD_TO_MERGE_TRAIN_WHEN_CHECKS_PASS,
        AutoMergeService::STRATEGY_MERGE_WHEN_CHECKS_PASS)
    end
  end

  describe '#available_strategies' do
    subject { service.available_strategies(merge_request) }

    let(:merge_request) do
      create(:merge_request, source_project: project)
    end

    let(:pipeline_status) { :running }

    before do
      create(
        :ci_pipeline,
        pipeline_status,
        ref: merge_request.source_branch,
        sha: merge_request.diff_head_sha,
        project: merge_request.source_project
      )

      merge_request.update_head_pipeline
      project.update!(merge_pipelines_enabled: true, merge_trains_enabled: true)
      stub_licensed_features(merge_trains: true, merge_pipelines: true)
    end

    it 'returns available strategies' do
      is_expected.to eq(['add_to_merge_train_when_checks_pass'])
    end

    context 'when merge train license is not available' do
      before do
        stub_licensed_features(merge_trains: false)
      end

      it 'returns base strategies' do
        is_expected.to eq(['merge_when_checks_pass'])
      end
    end

    context 'when pipeline is finished' do
      let(:pipeline_status) { :success }

      it 'returns available strategies' do
        is_expected.to eq(['merge_train'])
      end

      context 'when merge train license is not available' do
        before do
          stub_licensed_features(merge_trains: false)
        end

        it 'has no auto-merge strategies' do
          is_expected.to be_empty
        end
      end
    end

    # The merge request ran on a train, the train pipeline failed and it was dropped. A push
    # to the busy target branch then marks it unchecked, so the conflict check reports
    # `checking` and merge_train drops out, leaving only the strategy that can never finish.
    # See https://gitlab.com/gitlab-org/gitlab/-/issues/627635.
    context 'when the head pipeline is a failed merge train pipeline and merge_status is stale' do
      let(:pipeline_status) { :failed }

      before do
        merge_request.diff_head_pipeline.update!(
          ref: merge_request.train_ref_path,
          target_sha: merge_request.target_branch_sha,
          merge_request: merge_request
        )
        MergeRequest.where(id: merge_request.id).update_all(merge_status: :unchecked)
        merge_request.reload
      end

      it 'still prefers the merge train strategy', :aggregate_failures do
        is_expected.to include('merge_train')
        expect(service.preferred_strategy(merge_request)).to eq('merge_train')
      end

      context 'when auto_merge_readd_to_train_after_completed_pipeline is disabled' do
        before do
          stub_feature_flags(auto_merge_readd_to_train_after_completed_pipeline: false)
        end

        it 'drops the merge train strategy' do
          is_expected.not_to include('merge_train')
        end
      end
    end
  end
end
