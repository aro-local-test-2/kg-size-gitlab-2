# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeTrains::CheckStatusService, feature_category: :merge_trains do
  let_it_be_with_reload(:project) do
    create(:project, :repository, merge_pipelines_enabled: true, merge_trains_enabled: true)
  end

  let_it_be(:maintainer) { create(:user, maintainer_of: project) }

  let(:service) { described_class.new(project, maintainer) }

  before do
    stub_licensed_features(merge_pipelines: true, merge_trains: true)
  end

  describe '#execute' do
    subject { service.execute(target_project, target_branch, newrev) }

    let(:target_project) { project }
    let(:target_branch) { 'master' }
    let(:newrev) { Digest::SHA1.hexdigest 'test' }

    context 'when there is at least one merge request on the train' do
      let!(:merged_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'feature', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked', status: MergeTrains::Car.state_machines[:status].states[:merged].value)
      end

      let!(:active_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'improve/awesome', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked')
      end

      before do
        merged_merge_request.mark_as_merged!
        merged_merge_request.update_column(:merge_commit_sha, merge_commit_sha_1)
      end

      context 'when new revision is included in merge train history' do
        let!(:merge_commit_sha_1) { Digest::SHA1.hexdigest 'test' }

        it 'does not outdate the merge train pipeline' do
          expect_next_instance_of(MergeTrains::Train) do |train|
            expect(train)
              .to receive(:sha_exists_in_history?)
              .and_return(true)
              .and_call_original

            expect(train).not_to receive(:first_active_car)
          end

          expect_any_instance_of(MergeTrains::Car).not_to receive(:outdate_pipeline)

          subject
        end
      end

      context 'when new revision is not included in merge train history' do
        let!(:merge_commit_sha_1) { Digest::SHA1.hexdigest 'other' }

        it 'outdates the merge train pipeline' do
          expect_next_found_instance_of(MergeTrains::Car) do |car|
            expect(car).to receive(:outdate_pipeline)
          end

          subject
        end
      end
    end

    # Regression tests for https://gitlab.com/gitlab-org/gitlab/-/issues/741014
    context 'when a skip-merge race window is active (car exists, in_progress SHA matches newrev)' do
      let(:skip_merge_sha) { Digest::SHA1.hexdigest 'skip-merge' }
      let(:newrev) { skip_merge_sha }

      let!(:off_train_mr) do
        create(:merge_request,
          source_project: project,
          target_project: project,
          source_branch: 'fix-bug',
          target_branch: 'master')
      end

      let!(:active_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'improve/awesome', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked')
      end

      before do
        off_train_mr.lock_mr!
        off_train_mr.update_columns(in_progress_merge_commit_sha: skip_merge_sha)
        MergeTrains::Car.insert_skip_merged_car_for(off_train_mr, maintainer)
      end

      it 'does not outdate the merge train pipeline' do
        expect_any_instance_of(MergeTrains::Car).not_to receive(:outdate_pipeline)

        subject
      end
    end

    context 'when a skip-merge is complete (MR merged, SHA persisted on MR)' do
      let(:skip_merge_sha) { Digest::SHA1.hexdigest 'skip-merge-done' }
      let(:newrev) { skip_merge_sha }

      let!(:off_train_mr) do
        create(:merge_request,
          source_project: project,
          target_project: project,
          source_branch: 'fix-bug',
          target_branch: 'master')
      end

      let!(:active_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'improve/awesome', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked')
      end

      before do
        off_train_mr.lock_mr!
        MergeTrains::Car.insert_skip_merged_car_for(off_train_mr, maintainer)
        off_train_mr.update_columns(
          in_progress_merge_commit_sha: nil,
          merged_commit_sha: skip_merge_sha
        )
        off_train_mr.mark_as_merged!
      end

      it 'does not outdate the merge train pipeline' do
        expect_any_instance_of(MergeTrains::Car).not_to receive(:outdate_pipeline)

        subject
      end
    end

    context 'when a normal off-train merge (without skip_merge_train) is in progress' do
      let(:normal_merge_sha) { Digest::SHA1.hexdigest 'normal-merge' }
      let(:newrev) { normal_merge_sha }

      let!(:normal_mr) do
        create(:merge_request,
          source_project: project,
          target_project: project,
          source_branch: 'fix-bug',
          target_branch: 'master')
      end

      let!(:active_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'improve/awesome', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked')
      end

      before do
        # Normal merge: MR is locked and in_progress SHA is set, but NO skip_merged car.
        normal_mr.lock_mr!
        normal_mr.update_columns(in_progress_merge_commit_sha: normal_merge_sha)
        # Deliberately do NOT call insert_skip_merged_car_for
      end

      it 'outdates the merge train pipeline (normal invalidation preserved)' do
        expect_next_found_instance_of(MergeTrains::Car) do |car|
          expect(car).to receive(:outdate_pipeline)
        end

        subject
      end
    end

    context 'when an unexpected commit lands while a skip-merge is in flight (newrev differs from in_progress SHA)' do
      let(:skip_merge_sha) { Digest::SHA1.hexdigest 'skip-merge' }
      let(:unexpected_sha) { Digest::SHA1.hexdigest 'unexpected' }
      let(:newrev) { unexpected_sha }

      let!(:off_train_mr) do
        create(:merge_request,
          source_project: project,
          target_project: project,
          source_branch: 'fix-bug',
          target_branch: 'master')
      end

      let!(:active_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'improve/awesome', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked')
      end

      before do
        off_train_mr.lock_mr!
        # in_progress SHA is skip_merge_sha, but newrev is unexpected_sha - no match
        off_train_mr.update_columns(in_progress_merge_commit_sha: skip_merge_sha)
        MergeTrains::Car.insert_skip_merged_car_for(off_train_mr, maintainer)
      end

      it 'outdates the merge train pipeline' do
        expect_next_found_instance_of(MergeTrains::Car) do |car|
          expect(car).to receive(:outdate_pipeline)
        end

        subject
      end
    end

    context 'when the skip_merged car targets a different branch' do
      let(:skip_merge_sha) { Digest::SHA1.hexdigest 'skip-merge' }
      let(:newrev) { skip_merge_sha }

      let!(:off_train_mr) do
        create(:merge_request,
          source_project: project,
          target_project: project,
          source_branch: 'fix-bug',
          target_branch: 'other-branch')
      end

      let!(:active_merge_request) do
        create(:merge_request, :on_train,
          train_creator: maintainer,
          source_branch: 'improve/awesome', source_project: project,
          target_branch: 'master', target_project: project,
          merge_status: 'unchecked')
      end

      before do
        off_train_mr.lock_mr!
        off_train_mr.update_columns(in_progress_merge_commit_sha: skip_merge_sha)
        MergeTrains::Car.insert_skip_merged_car_for(off_train_mr, maintainer)
      end

      it 'outdates the merge train pipeline (different branch does not suppress)' do
        expect_next_found_instance_of(MergeTrains::Car) do |car|
          expect(car).to receive(:outdate_pipeline)
        end

        subject
      end
    end

    context 'when there are no merge requests on train' do
      it 'does not raise error' do
        expect_next_instance_of(MergeTrains::Train) do |train|
          expect(train)
            .to receive(:sha_exists_in_history?)
            .and_return(false)
            .and_call_original
        end

        expect { subject }.not_to raise_error
      end
    end

    context 'when merge train is disabled on the project' do
      before do
        project.update!(merge_pipelines_enabled: false)
      end

      it 'returns immediately without loading any Trains to check the history of' do
        expect(MergeTrains::Train).not_to receive(:new)

        subject
      end
    end
  end
end
