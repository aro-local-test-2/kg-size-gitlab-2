# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeTrains::Train, feature_category: :merge_trains do
  include MergeTrainsHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:target_project) { create(:project, :repository) }
  let_it_be_with_reload(:merge_request) do
    create_merge_request_on_train(project: target_project, author: target_project.creator)
  end

  let_it_be(:other_project) { create(:project) }

  let(:train) { described_class.new(target_project, merge_request.target_branch) }

  def create_merge_train_car(*traits, target_project:, target_branch:)
    create(:merge_train_car, *traits,
      target_project: target_project,
      target_branch: target_branch,
      user: target_project.creator,
      merge_request: create(:merge_request, :skip_diff_creation,
        source_project: target_project, source_branch: "lightweight-car-#{SecureRandom.hex(4)}"),
      pipeline: create(:ci_pipeline, project: target_project))
  end

  shared_examples 'fetches the requested trains' do
    it 'returns relevant merge trains' do
      branches = trains.map(&:target_branch)

      expect(branches).to contain_exactly(*expected_branches)
    end
  end

  describe '.all_for_project' do
    subject(:trains) { described_class.all_for_project(target_project) }

    before_all do
      create_merge_train_car(target_project: target_project, target_branch: 'master')
      create_merge_train_car(target_project: target_project, target_branch: 'feature-1')
      create_merge_train_car(:merged, target_project: target_project, target_branch: 'feature-2')
      create_merge_train_car(target_project: other_project, target_branch: 'master')
    end

    it_behaves_like 'fetches the requested trains' do
      let(:expected_branches) { %w[master feature-1] }
    end
  end

  describe '.all_for' do
    subject(:trains) { described_class.all_for(target_project, **params) }

    before_all do
      create_merge_train_car(target_project: target_project, target_branch: 'master')
      create_merge_train_car(target_project: target_project, target_branch: 'master')
      create_merge_train_car(:merged, target_project: target_project, target_branch: 'master')
      create_merge_train_car(target_project: target_project, target_branch: 'feature-1')
      create_merge_train_car(:merged, target_project: target_project, target_branch: 'feature-2')
      create_merge_train_car(target_project: other_project, target_branch: 'master')
    end

    context 'when only the project is provided' do
      let(:params) { {} }

      it_behaves_like 'fetches the requested trains' do
        let(:expected_branches) { %w[master feature-1 feature-2] }
      end
    end

    context 'when target_branches are provided' do
      let(:params) { { target_branch: %w[feature-1 feature-2] } }

      it_behaves_like 'fetches the requested trains' do
        let(:expected_branches) { %w[feature-1 feature-2] }
      end

      context 'when status is provided' do
        before do
          params[:status] = described_class::STATUSES[:completed]
        end

        it_behaves_like 'fetches the requested trains' do
          let(:expected_branches) { %w[feature-2] }
        end
      end
    end

    context 'when status is provided' do
      let(:params) { { status: described_class::STATUSES[:completed] } }

      it_behaves_like 'fetches the requested trains' do
        let(:expected_branches) { %w[feature-2] }
      end
    end
  end

  describe '.project_using_ff?' do
    subject { described_class.project_using_ff?(target_project) }

    where(:merge_trains_enabled, :ff_merge_method, :expected) do
      true  | true  | true
      true  | false | false
      false | true  | false
    end

    with_them do
      before do
        allow(target_project).to receive_messages(merge_trains_enabled?: merge_trains_enabled,
          ff_merge_must_be_possible?: ff_merge_method)
      end

      it { is_expected.to eq expected }
    end
  end

  describe '#refresh_async' do
    subject(:refresh_async) { train.refresh_async }

    it 'schedules a worker' do
      expect(MergeTrains::RefreshWorker)
        .to receive(:perform_async).with(train.project_id, train.target_branch)

      refresh_async
    end
  end

  context 'with a shared set of active and completed cars' do
    before_all do
      create_merge_train_car(target_project: target_project, target_branch: 'master')
      create_merge_train_car(:merged, target_project: target_project, target_branch: 'feature-2')
      create_merge_train_car(target_project: other_project, target_branch: 'master')
    end

    describe '#active?' do
      context 'when the train contains both completed and idle cars' do
        let(:train) do
          create_merge_train_car(:merged, target_project: target_project, target_branch: 'master').train
        end

        it 'returns true' do
          expect(train.active?).to be(true)
        end
      end

      context 'when the train contains only completed cars' do
        let(:train) do
          create_merge_train_car(:merged, target_project: target_project, target_branch: 'feature-2').train
        end

        it 'returns false' do
          expect(train.active?).to be(false)
        end
      end
    end

    describe '#completed?' do
      context 'when the train contains both completed and idle cars' do
        let(:train) do
          create_merge_train_car(:merged, target_project: target_project, target_branch: 'master').train
        end

        it 'returns true' do
          expect(train.completed?).to be(false)
        end
      end

      context 'when the train contains only completed cars' do
        let(:train) do
          create_merge_train_car(:merged, target_project: target_project, target_branch: 'feature-2').train
        end

        it 'returns false' do
          expect(train.completed?).to be(true)
        end
      end
    end
  end

  describe '#all_active_cars_indexed' do
    it 'returns indexed active cars' do
      result = train.all_active_cars_indexed

      expect(result).to eq(train.all_active_cars.indexed)
    end
  end

  describe 'partition-aware pipeline preloading' do
    let_it_be(:pipeline) { create(:ci_pipeline, project: target_project) }

    before_all do
      merge_request.merge_train_car.update!(pipeline: pipeline)
    end

    it 'routes the pipeline preload through the partition-aware hook on active cars' do
      expect(Gitlab::Ci::Pipeline::BulkByIdLookup).to receive(:new).and_call_original

      cars = train.all_active_cars_indexed.preload(pipeline: { project: :route }).load.to_a

      expect(cars.map { |car| car.association(:pipeline).loaded? }).to all(be(true))
    end

    it 'routes the pipeline preload through the partition-aware hook on completed cars' do
      merge_request.merge_train_car.update_column(
        :status, MergeTrains::Car.state_machines[:status].states[:merged].value
      )

      expect(Gitlab::Ci::Pipeline::BulkByIdLookup).to receive(:new).and_call_original

      train.completed_cars.preload(pipeline: { project: :route }).load
    end
  end

  describe '#all_active_cars' do
    subject { train.all_active_cars }

    it 'returns the merge request car' do
      is_expected.to eq([merge_request.merge_train_car])
    end

    context 'when another merge request is opened but not on merge train' do
      let!(:other_merge_request) do
        create(:merge_request, :skip_diff_creation,
          source_project: target_project,
          source_branch: 'improve/awesome',
          target_branch: merge_request.target_branch)
      end

      it { is_expected.to eq([merge_request.merge_train_car]) }
    end

    context 'with another open merge request on the merge train' do
      let!(:merge_request_2) do
        create_merge_request_on_train(project: target_project, source_branch: 'improve/awesome',
          author: target_project.creator)
      end

      it 'returns both cars in order of creation' do
        is_expected.to eq([merge_request.merge_train_car, merge_request_2.merge_train_car])
      end
    end

    context 'with another open merge request that has already been merged' do
      let!(:merged_merge_request) do
        create_merge_request_on_train(project: target_project, status: :merged, source_branch: 'improve/awesome',
          author: target_project.creator)
      end

      it 'does not return the merged car' do
        is_expected.to eq([merge_request.merge_train_car])
      end
    end
  end

  describe '#sha_exists_in_history?' do
    subject { train.sha_exists_in_history?(target_sha, limit: limit) }

    let(:target_sha) { '' }
    let(:limit) { 20 }

    context 'when there is a merge request on train' do
      let(:merge_commit_sha_1) { OpenSSL::Digest.hexdigest('SHA256', 'test-1') }
      let(:target_sha) { merge_commit_sha_1 }

      context 'when the merge request has already been merging' do
        let!(:merge_request) do
          create_merge_request_on_train(project: target_project, status: :merging, source_branch: 'improve/awesome',
            author: target_project.creator)
        end

        before do
          merge_request.update_column(:in_progress_merge_commit_sha, merge_commit_sha_1)
        end

        it { is_expected.to be(true) }
      end

      context 'when the merge request has already been merged' do
        let!(:merge_request) do
          create_merge_request_on_train(project: target_project, status: :merged, source_branch: 'improve/awesome',
            author: target_project.creator)
        end

        before do
          merge_request.update_column(:merge_commit_sha, merge_commit_sha_1)
        end

        it { is_expected.to be(true) }
      end

      context 'when the merge request has been fast-forward merged from an internal ref' do
        let!(:merge_request) do
          create_merge_request_on_train(project: target_project, status: :merged, source_branch: 'improve/awesome',
            author: target_project.creator)
        end

        before do
          merge_request.update_column(:merged_commit_sha, merge_commit_sha_1)
        end

        it { is_expected.to be(true) }
      end

      context 'when there is another merge request on train and it has been merged' do
        let_it_be_with_reload(:merge_request_2) do
          create_merge_request_on_train(project: target_project, status: :merged, source_branch: 'improve/awesome',
            author: target_project.creator)
        end

        let_it_be(:merge_commit_sha_2) { OpenSSL::Digest.hexdigest('SHA256', 'test-2') }
        let(:target_sha) { merge_commit_sha_2 }

        before_all do
          merge_request_2.update_column(:merge_commit_sha, merge_commit_sha_2)
        end

        it { is_expected.to be(true) }

        context 'when limit is 1' do
          let(:limit) { 1 }
          let(:target_sha) { merge_commit_sha_1 }

          it { is_expected.to be(false) }
        end
      end

      context 'when the merge request has not been merged yet' do
        it { is_expected.to be(false) }
      end
    end

    context 'when there are no merge requests on train' do
      it { is_expected.to be(false) }
    end

    # Regression tests for https://gitlab.com/gitlab-org/gitlab/-/issues/741014
    context 'when a skip-merge is in progress (race window: car exists, SHA not yet on MR)' do
      # in_progress_merge_commit_sha is set during the Gitaly merge and equals newrev.
      let(:skip_merge_sha) { OpenSSL::Digest.hexdigest('SHA256', 'skip-merge') }
      let(:target_sha) { skip_merge_sha }

      let!(:off_train_mr) do
        create(:merge_request,
          source_project: target_project,
          target_project: target_project,
          source_branch: 'fix-bug',
          target_branch: merge_request.target_branch)
      end

      before do
        # Simulate the race window: car created, in_progress SHA set, push not yet done.
        off_train_mr.lock_mr!
        off_train_mr.update_columns(in_progress_merge_commit_sha: skip_merge_sha)
        MergeTrains::Car.insert_skip_merged_car_for(off_train_mr, create(:user))
      end

      it { is_expected.to be(true) }

      context 'when the skip_merged car targets a different branch' do
        let!(:off_train_mr) do
          create(:merge_request,
            source_project: target_project,
            target_project: target_project,
            source_branch: 'fix-bug',
            target_branch: 'other-branch')
        end

        # The outer before block runs with the overridden off_train_mr (targeting
        # 'other-branch'), so the car is on 'other-branch', not the train's branch.
        it { is_expected.to be(false) }
      end

      context 'when the skip_merged car targets a different project' do
        let_it_be(:other_project) { create(:project, :repository) }

        let!(:off_train_mr) do
          create(:merge_request,
            source_project: other_project,
            target_project: other_project,
            source_branch: 'fix-bug',
            target_branch: merge_request.target_branch)
        end

        # The outer before block runs with the overridden off_train_mr (targeting
        # other_project), so the car is on other_project, not target_project.
        it { is_expected.to be(false) }
      end

      context 'when the skip-merge is complete (MR merged, SHA persisted, car present)' do
        # After the full merge flow: car exists, SHA is on the MR, MR is merged.
        # in_progress_merge_commit_sha is cleared; merged_commit_sha is set.
        before do
          off_train_mr.update_columns(
            in_progress_merge_commit_sha: nil,
            merged_commit_sha: skip_merge_sha
          )
          off_train_mr.mark_as_merged!
        end

        it { is_expected.to be(true) }
      end
    end

    # Earliest race sub-window: MR not yet locked, no car created yet.
    # This sub-window is not covered by the fix (it is extremely brief).
    # The fix covers the window between the git push and merged_commit_sha
    # persistence, which is the dangerous window.
    context 'when the MR is not locked (car not yet created — earliest race window)' do
      let(:skip_merge_sha) { OpenSSL::Digest.hexdigest('SHA256', 'skip-merge') }
      let(:target_sha) { skip_merge_sha }

      let!(:off_train_mr) do
        create(:merge_request,
          source_project: target_project,
          target_project: target_project,
          source_branch: 'fix-bug',
          target_branch: merge_request.target_branch)
      end

      before do
        # off_train_mr remains in opened state - no lock, no car, no in_progress SHA
        off_train_mr.update_columns(merged_commit_sha: skip_merge_sha)
      end

      it { is_expected.to be(false) }
    end

    # Critical regression: a normal direct merge (without skip_merge_train=true)
    # must NOT suppress train invalidation. Normal merges never have a skip_merged
    # car, so the narrow check must not match them even when the MR is locked.
    context 'when a normal off-train merge (without skip_merge_train) is in progress' do
      let(:normal_merge_sha) { OpenSSL::Digest.hexdigest('SHA256', 'normal-merge') }
      let(:target_sha) { normal_merge_sha }

      let!(:normal_mr) do
        create(:merge_request,
          source_project: target_project,
          target_project: target_project,
          source_branch: 'fix-bug',
          target_branch: merge_request.target_branch)
      end

      before do
        # Normal merge: MR is locked and in_progress SHA is set, but NO skip_merged car.
        normal_mr.lock_mr!
        normal_mr.update_columns(in_progress_merge_commit_sha: normal_merge_sha)
        # Deliberately do NOT call insert_skip_merged_car_for
      end

      # The SHA is not in completed_cars history and there is no skip_merged car,
      # so sha_exists_in_history? must return false - train invalidation proceeds.
      it { is_expected.to be(false) }
    end

    # Genuinely unexpected commit (not from any merge flow) must still trigger
    # train invalidation.
    context 'when an unexpected commit lands on the branch' do
      let(:unexpected_sha) { OpenSSL::Digest.hexdigest('SHA256', 'unexpected') }
      let(:target_sha) { unexpected_sha }

      it { is_expected.to be(false) }
    end
  end

  describe '#refreshable_cars' do
    subject(:refreshable_cars) { train.refreshable_cars }

    let_it_be(:idle_car) do
      create_merge_train_car(:idle, target_project: target_project, target_branch: merge_request.target_branch)
    end

    let_it_be(:merging_car) do
      create_merge_train_car(:merging, target_project: target_project, target_branch: merge_request.target_branch)
    end

    let_it_be(:merged_car) do
      create_merge_train_car(:merged, target_project: target_project, target_branch: merge_request.target_branch)
    end

    let_it_be(:other_branch_car) do
      create_merge_train_car(:idle, target_project: target_project, target_branch: 'feature-1')
    end

    it 'returns active and merging cars for the train branch, ordered by id' do
      expect(refreshable_cars).to eq([merge_request.merge_train_car, idle_car, merging_car])
    end

    it 'excludes merged cars and cars on other branches' do
      expect(refreshable_cars).not_to include(merged_car, other_branch_car)
    end

    it 'loads what a refresh reads off each car without querying per car' do
      cars = refreshable_cars

      expect do
        cars.each do |car|
          car.user
          car.pipeline
          car.merge_request.source_project
          car.merge_request.latest_merge_request_diff
          car.merge_request.running_scan_result_policy_violations.to_a
        end
      end.not_to exceed_all_query_limit(0)
    end

    it 'reuses the train project rather than reloading it per association', :aggregate_failures do
      cars = refreshable_cars
      car = cars.find { |candidate| candidate.merge_request_id == merge_request.id }

      expect(cars.map(&:target_project)).to all(equal(train.project))
      expect(car.merge_request.target_project).to equal(train.project)
    end

    it 'resolves pipelines through the partition-aware lookup', :aggregate_failures do
      expect(Gitlab::Ci::Pipeline::BulkByIdLookup).to receive(:new).and_call_original

      expect(refreshable_cars.map { |car| car.association(:pipeline).loaded? }).to all(be(true))
    end

    context 'with a limit' do
      subject(:refreshable_cars) { train.refreshable_cars(limit: 1) }

      it 'limits the number of returned cars' do
        expect(refreshable_cars).to eq([merge_request.merge_train_car])
      end
    end

    context 'with a warm partition cache covering the pipeline ids' do
      let(:cars) { [merge_request.merge_train_car, idle_car, merging_car] }

      before do
        min_id, max_id = cars.map(&:pipeline_id).minmax
        create(:ci_partition, id: idle_car.pipeline.partition_id, pipelines_id_range: (min_id..max_id))
        Gitlab::Ci::Pipeline::PartitionCache.invalidate
      end

      after do
        Gitlab::Ci::Pipeline::PartitionCache.invalidate
      end

      it 'prunes the pipeline lookup by partition_id' do
        recorder = ActiveRecord::QueryRecorder.new { refreshable_cars }

        expect(recorder.log).to include(a_string_matching(/p_ci_pipelines.*partition_id/))
      end
    end
  end

  describe '#first_active_car' do
    subject(:first_active_car) { train.first_active_car }

    let(:first) { instance_double(MergeTrains::Car) }
    let(:last) { instance_double(MergeTrains::Car) }

    let(:cars) { [first, last] }

    it 'returns the first active car' do
      expect(first_active_car).to eq(merge_request.merge_train_car)
    end

    context 'when there are no cars' do
      before do
        MergeTrains::Car.delete_all
      end

      it 'returns nil' do
        expect(first_active_car).to be_nil
      end
    end

    context 'when the first car is merging with no merged cars after it' do
      before do
        merge_request.merge_train_car.update_column(
          :status, MergeTrains::Car.state_machines[:status].states[:merging].value
        )
      end

      it 'does not return the merging car via first_active_car' do
        expect(train.first_active_car).to be_nil
      end
    end
  end

  describe '#car_count' do
    subject(:car_count) { train.car_count }

    let(:cars) { [instance_double(MergeTrains::Car), instance_double(MergeTrains::Car)] }

    it 'returns the count of the all_active_cars relation' do
      allow_next_instance_of(MergeTrains::Train) do |train|
        allow(train).to receive(:all_active_cars).and_return(cars)
      end

      expect(car_count).to eq(cars.length)
    end
  end
end
