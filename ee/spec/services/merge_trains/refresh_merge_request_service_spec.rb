# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeTrains::RefreshMergeRequestService, feature_category: :source_code_management do
  let(:project) { create(:project, :repository, merge_pipelines_enabled: true, merge_trains_enabled: true) }
  let_it_be(:maintainer) { create(:user) }

  let(:service) { described_class.new(project, maintainer, require_recreate: require_recreate) }
  let(:require_recreate) { false }
  let(:expected_create_mergeable_ref) { true }

  before do
    project.add_maintainer(maintainer)
    stub_licensed_features(merge_pipelines: true, merge_trains: true)
    project.update!(merge_pipelines_enabled: true, merge_trains_enabled: true) unless project.merge_pipelines_enabled == true && project.merge_trains_enabled == true
  end

  describe '#execute' do
    subject { service.execute(merge_request) }

    let!(:merge_request) do
      create(:merge_request, :on_train,
        train_creator: maintainer,
        source_branch: 'feature', source_project: project,
        target_branch: 'master', target_project: project)
    end

    shared_examples_for 'drops the merge request from the merge train' do
      let(:expected_reason) { 'unknown' }

      specify do
        expect_next_instance_of(AutoMerge::MergeTrainService) do |service|
          expect(service).to receive(:abort).with(merge_request, expected_reason, hash_including(process_next: false))
        end

        subject
      end
    end

    shared_examples_for 'creates a pipeline for merge train' do
      let(:previous_ref) { 'refs/heads/master' }

      specify do
        expect_next_instance_of(MergeTrains::CreatePipelineService, project, maintainer) do |pipeline_service|
          allow(pipeline_service).to receive(:execute) { { status: :success, pipeline: pipeline } }
          expect(pipeline_service).to receive(:execute).with(merge_request, previous_ref, expected_create_mergeable_ref)
        end

        result = subject
        expect(result[:status]).to eq(:success)
        expect(result[:pipeline_created]).to be(true)
        expect(merge_request.merge_train_car).to be_fresh
      end
    end

    shared_examples_for 'cancels and recreates a pipeline for the merge train' do
      let(:previous_ref) { 'refs/heads/master' }

      it 'cancels and recreates a pipeline for the merge train', :sidekiq_might_not_need_inline do
        expect_next_instance_of(MergeTrains::CreatePipelineService, project, maintainer) do |pipeline_service|
          allow(pipeline_service).to receive(:execute) { { status: :success, pipeline: create(:ci_pipeline) } }
          expect(pipeline_service).to receive(:execute).with(merge_request, previous_ref, expected_create_mergeable_ref)
        end

        result = subject
        new_pipeline = merge_request.merge_train_car.pipeline
        pipeline.reset

        expect(result[:status]).to eq(:success)
        expect(result[:pipeline_created]).to be(true)
        expect(pipeline.status).to eq('canceled')
        expect(pipeline.auto_canceled_by_id).to eq(new_pipeline.id)
      end
    end

    shared_examples_for 'does not create a pipeline' do
      specify do
        expect(service).not_to receive(:create_pipeline!)

        result = subject
        expect(result[:status]).to eq(:success)
        expect(result[:pipeline_created]).to be_falsy
      end
    end

    shared_examples_for 'merges the merge request' do
      specify do
        expect(merge_request).to receive(:schedule_cleanup_refs).with(only: :train)
        expect(merge_request.merge_train_car).to receive(:start_merge!).and_call_original
        expect(merge_request.merge_train_car).to receive(:finish_merge!).and_call_original
        expect_next_instance_of(MergeRequests::MergeService, project: project, current_user: maintainer, params: instance_of(HashWithIndifferentAccess)) do |service|
          expect(service).to receive(:execute).with(merge_request, skip_discussions_check: true, check_mergeability_retry_lease: true).and_call_original
        end

        expect { subject }.to change { merge_request.merge_train_car.status_name }.from(:fresh).to(:merged)
        expect(merge_request.state).to eq("merged")
      end
    end

    context 'when the merge request is locked but already merged in the repository' do
      let(:pipeline) { create(:ci_pipeline, :success, project: project) }

      before do
        allow(merge_request).to receive_messages(
          locked?: true,
          merged?: false,
          merged_in_repository?: true
        )

        merge_request.merge_train_car.update!(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          pipeline: pipeline,
          updated_at: 3.hours.ago
        )
        merge_request.update!(
          state_id: MergeRequest.available_states[:locked],
          in_progress_merge_commit_sha: 'abc123',
          updated_at: 3.hours.ago
        )
      end

      it 'reconciles via PostMergeService and finishes the train car' do
        expect_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
          expect(post_merge).to receive(:execute).with(merge_request)
        end
        expect(merge_request.merge_train_car).to receive(:finish_merge!).and_call_original

        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(
            message: 'Unstuck stuck merge train merge',
            action: 'reconciled_silently_merged'
          )
        )
        subject
      end

      it 'does not call handle_locked_stuck_car (no force-unlock attempt)' do
        allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
          allow(post_merge).to receive(:execute)
        end
        allow(merge_request.merge_train_car).to receive(:finish_merge!).and_return(true)

        expect(merge_request).not_to receive(:unlock_mr)

        subject
      end
    end

    context 'when the merge request is silently merged but the reconcile flag is disabled' do
      let(:pipeline) { create(:ci_pipeline, :success, project: project) }

      before do
        stub_feature_flags(merge_trains_reconcile_silently_merged: false)

        merge_request.merge_train_car.update!(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          pipeline: pipeline,
          updated_at: 3.hours.ago
        )
        merge_request.update!(
          state_id: MergeRequest.available_states[:locked],
          in_progress_merge_commit_sha: 'abc123',
          updated_at: 3.hours.ago
        )
        allow(merge_request).to receive_messages(
          locked?: true,
          merged?: false,
          merged_in_repository?: true
        )
      end

      it 'falls back to the legacy bare mark_as_merged! without running PostMergeService' do
        expect(merge_request).to receive(:mark_as_merged!).and_call_original
        expect(merge_request.merge_train_car).to receive(:finish_merge!).and_call_original
        expect(MergeRequests::PostMergeService).not_to receive(:new)

        subject
      end
    end

    context 'when the silently-merged reconciliation fails' do
      let(:pipeline) { create(:ci_pipeline, :success, project: project) }

      before do
        allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
          allow(post_merge).to receive(:execute).and_raise(ActiveRecord::QueryCanceled.new('boom'))
        end
        allow(merge_request).to receive(:unlock_mr).and_return(true)
        merge_request.merge_train_car.update!(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          pipeline: pipeline,
          updated_at: 3.hours.ago
        )
        merge_request.update!(
          state_id: MergeRequest.available_states[:locked],
          in_progress_merge_commit_sha: 'abc123',
          updated_at: 3.hours.ago
        )
        allow(merge_request).to receive_messages(
          locked?: true,
          merged?: false,
          merged_in_repository?: true
        )
      end

      it 'tracks the exception and falls back to handle_locked_stuck_car' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(ActiveRecord::QueryCanceled),
          hash_including(handler: 'handle_silently_merged_stuck_car')
        )

        expect(merge_request).to receive(:unlock_mr)

        subject
      end
    end

    context 'when a post-merge step fails after the MR was already marked merged' do
      let(:pipeline) { create(:ci_pipeline, :success, project: project) }

      before do
        merge_request.merge_train_car.update!(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          pipeline: pipeline,
          updated_at: 3.hours.ago
        )
        merge_request.update!(
          state_id: MergeRequest.available_states[:locked],
          in_progress_merge_commit_sha: 'abc123',
          updated_at: 3.hours.ago
        )
        allow(merge_request).to receive_messages(
          locked?: true,
          merged_in_repository?: true
        )

        # PostMergeService marks the MR merged as its first step; simulate a later
        # step failing after that write has already landed.
        allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
          allow(post_merge).to receive(:execute) do
            merge_request.update_column(:state_id, MergeRequest.available_states[:merged])
            raise ActiveRecord::QueryCanceled, 'boom'
          end
        end
      end

      it 'finishes the car instead of aborting the already-merged MR' do
        expect(merge_request).not_to receive(:unlock_mr)

        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(action: 'reconciled_silently_merged')
        )

        subject

        # The car is finished (not destroyed by an abort) and the MR stays merged.
        expect(merge_request.reset.merged?).to be(true)
        expect(merge_request.merge_train_car).to be_merged
      end
    end

    context 'when the merge request is locked and NOT merged in the repository' do
      let(:pipeline) { create(:ci_pipeline, :success, project: project) }

      before do
        merge_request.merge_train_car.update!(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          pipeline: pipeline,
          updated_at: 3.hours.ago
        )
        merge_request.update!(
          state_id: MergeRequest.available_states[:locked],
          in_progress_merge_commit_sha: 'abc123',
          updated_at: 3.hours.ago
        )
        allow(merge_request).to receive_messages(
          locked?: true,
          merged?: false,
          merged_in_repository?: false
        )
      end

      it 'falls through to handle_locked_stuck_car' do
        expect(merge_request).to receive(:unlock_mr).and_return(true)

        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(action: 'abort_merge_locked')
        )
        subject
      end
    end

    context 'when the merge request is open and not locked but stuck' do
      before do
        merge_request.merge_train_car.update_columns(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          updated_at: 3.hours.ago
        )
        merge_request.unlock_mr
        merge_request.update_columns(updated_at: 3.hours.ago)
      end

      it 'aborts without calling unlock_mr' do
        expect(merge_request).not_to receive(:unlock_mr)

        expect_next_instance_of(AutoMerge::MergeTrainService) do |svc|
          expect(svc).to receive(:abort).with(
            merge_request,
            a_string_matching(/the merge did not complete in time/),
            hash_including(process_next: false)
          )
        end

        subject
      end
    end

    context 'when an unexpected error occurs during execution' do
      let(:unexpected_error) { StandardError.new("boom") }

      before do
        allow(merge_request.merge_train_car).to receive_messages(
          requires_new_pipeline?: false,
          merge_ready_pipeline?: true
        )

        allow(service).to receive_messages(
          require_recreate?: false,
          create_pipeline!: nil
        )

        allow(service).to receive(:merge!).and_raise(unexpected_error)
      end

      it 'tracks the error and aborts with a ProcessError' do
        expect(Gitlab::ErrorTracking)
          .to receive(:track_exception)
          .with(
            unexpected_error,
            merge_request_id: merge_request.id,
            merge_request_iid: merge_request.iid,
            project_id: merge_request.target_project_id
          )

        expect(service).to receive(:abort) do |error|
          expect(error).to be_a(described_class::ProcessError)
          expect(error.message).to eq(
            "an unexpected error occurred. Correlation ID: #{Labkit::Correlation::CorrelationId.current_or_new_id}."
          )
        end

        subject
      end
    end

    context 'when merge pipelines project configuration is disabled' do
      before do
        project.update!(merge_pipelines_enabled: false)
      end

      it_behaves_like 'drops the merge request from the merge train' do
        let(:expected_reason) { 'merge trains are disabled for this project.' }
      end
    end

    context 'when merge trains not enabled' do
      before do
        project.update!(merge_trains_enabled: false)
      end

      it_behaves_like 'drops the merge request from the merge train' do
        let(:expected_reason) { 'merge trains are disabled for this project.' }
      end
    end

    context 'when merge request is not in a mergeable state' do
      context 'when merge request is a draft' do
        before do
          merge_request.update!(title: merge_request.draft_title)
        end

        it_behaves_like 'drops the merge request from the merge train' do
          let(:expected_reason) do
            'the merge request is marked as draft. ' \
              '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
          end
        end
      end

      context 'when the car is merging but not timed out and has no pipeline' do
        before do
          not_stuck_yet = (MergeTrains::Car::STUCK_AFTER - 5.minutes).ago
          car = merge_request.merge_train_car
          car.update_columns(pipeline_id: nil, updated_at: not_stuck_yet, status: MergeTrains::Car.state_machines[:status].states[:merging].value)
          car.reload
        end

        it 'does not unstick because not timed out' do
          expect(Gitlab::AppLogger).not_to receive(:warn).with(
            hash_including(message: 'Unstuck stuck merge train merge')
          )

          expect { subject }.to raise_error(MergeTrains::RefreshMergeRequestService::ConcurrencyError, /error/)
        end
      end

      context 'when merge request is not open' do
        before do
          allow(merge_request).to receive(:open?).and_return(false)
        end

        it_behaves_like 'drops the merge request from the merge train' do
          let(:expected_reason) do
            'the merge request is closed. ' \
              '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
          end
        end
      end

      context 'when merge request is broken' do
        before do
          allow(merge_request).to receive(:broken?).and_return(true)
        end

        it_behaves_like 'drops the merge request from the merge train' do
          let(:expected_reason) do
            'the merge request is broken. ' \
              '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
          end
        end
      end

      context 'when auto merge is not set' do
        before do
          # simulate clearing the auto merge parameters with a car present
          merge_request.update!(auto_merge_enabled: false, merge_user_id: nil)
        end

        it_behaves_like 'drops the merge request from the merge train' do
          let(:expected_reason) do
            'the merge request is not set to auto-merge.'
          end
        end
      end
    end

    context 'when the merge train car is in merging' do
      let(:pipeline) { create(:ci_pipeline, :success, project: project) }

      before do
        merge_request.merge_train_car.update!(
          status: MergeTrains::Car.state_machines[:status].states[:merging].value,
          pipeline: pipeline,
          updated_at: 3.hours.ago
        )
        merge_request.update!(
          state_id: MergeRequest.available_states[:locked],
          in_progress_merge_commit_sha: 'abc123',
          updated_at: 3.hours.ago
        )
      end

      context 'when the merge request is closed and car destroy fails' do
        before do
          merge_request.update!(state_id: MergeRequest.available_states[:closed])
          allow(merge_request.merge_train_car).to receive(:destroy).and_return(false)
        end

        it 'logs the failure and returns success' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(
              message: 'Unstuck stuck merge train merge',
              action: 'destroy_failed'
            )
          )

          result = subject

          expect(result[:status]).to eq(:success)
        end
      end

      context 'when the merge request is open and stuck' do
        before do
          merge_request.unlock_mr
          merge_request.update_columns(updated_at: 3.hours.ago)
        end

        it 'aborts via open stuck car handler' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(
              message: 'Unstuck stuck merge train merge',
              action: 'abort_merge_open'
            )
          )

          expect_next_instance_of(AutoMerge::MergeTrainService) do |svc|
            expect(svc).to receive(:abort).with(
              merge_request,
              a_string_matching(/the merge did not complete in time/),
              hash_including(process_next: false)
            )
          end

          subject
        end
      end

      context 'when the merge request is closed and stuck' do
        before do
          merge_request.update!(state_id: MergeRequest.available_states[:closed])
        end

        it 'silently destroys the car' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(
              message: 'Unstuck stuck merge train merge',
              action: 'destroy_closed'
            )
          )

          result = subject

          expect(result[:status]).to eq(:success)
        end
      end

      context 'when the merge request has actually been merged' do
        before do
          merge_request.update!(state_id: MergeRequest.available_states[:merged])
        end

        it 'finishes the merge and logs the action' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(
              message: 'Unstuck stuck merge train merge',
              action: 'finish_merge'
            )
          )

          result = subject

          expect(result[:status]).to eq(:success)
        end
      end

      context 'when the merge request is in an unexpected state' do
        before do
          # Force an unrecognized state by stubbing all state checks to false
          allow(merge_request).to receive_messages(merged?: false, locked?: false, open?: false, closed?: false)
        end

        it 'tracks the exception and aborts' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(StandardError),
            hash_including(
              merge_request_id: merge_request.id,
              merge_request_iid: merge_request.iid,
              project_id: merge_request.target_project_id
            )
          )

          expect_next_instance_of(AutoMerge::MergeTrainService) do |svc|
            expect(svc).to receive(:abort).with(
              merge_request,
              a_string_matching(/the merge did not complete in time/),
              hash_including(process_next: false)
            )
          end

          subject
        end
      end

      context 'when the merge request is locked and stuck' do
        it 'unlocks the MR, aborts the merge, and drops from train' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(
              message: 'Unstuck stuck merge train merge',
              action: 'abort_merge_locked'
            )
          )

          expect_next_instance_of(AutoMerge::MergeTrainService) do |service|
            expect(service).to receive(:abort).with(
              merge_request,
              a_string_matching(/the merge did not complete in time/),
              hash_including(process_next: false)
            )
          end

          subject

          merge_request.reload
          expect(merge_request.state).to eq('opened')
        end

        context 'when the car has no pipeline' do
          before do
            merge_request.merge_train_car.update!(pipeline: nil)
          end

          it 'is not considered stuck' do
            expect { subject }.to raise_error(MergeTrains::RefreshMergeRequestService::ConcurrencyError, /error/)
          end
        end
      end

      context 'when the car is merging but not stuck yet' do
        before do
          merge_request.merge_train_car.update!(updated_at: 10.minutes.ago)
          merge_request.update!(updated_at: 10.minutes.ago)
        end

        it 'does not unstick' do
          expect(Gitlab::AppLogger).not_to receive(:warn).with(
            hash_including(message: 'Unstuck stuck merge train merge')
          )

          expect { subject }.to raise_error(MergeTrains::RefreshMergeRequestService::ConcurrencyError, /error/)
        end
      end

      context 'when the car is merging but not timed out' do
        let(:pipeline) { create(:ci_pipeline, :running, project: project) }

        before do
          not_stuck_yet = (MergeTrains::Car::STUCK_AFTER - 5.minutes).ago
          merge_request.merge_train_car.update_columns(updated_at: not_stuck_yet)
          merge_request.update_columns(updated_at: not_stuck_yet)
        end

        it 'does not unstick' do
          expect(Gitlab::AppLogger).not_to receive(:warn).with(
            hash_including(message: 'Unstuck stuck merge train merge')
          )

          expect { subject }.to raise_error(MergeTrains::RefreshMergeRequestService::ConcurrencyError, /error/)
        end
      end

      context 'when the merge request is locked and normal unlock fails due to validation errors' do
        before do
          allow(merge_request).to receive(:unlock_mr).and_return(false, true)
          allow(merge_request).to receive(:add_to_locked_set).and_call_original
        end

        it 'force unlocks, aborts the train car and hands over to another unlock service' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(
              message: 'Unstuck stuck merge train merge',
              action: 'forced_unlock'
            )
          )

          expect_next_instance_of(AutoMerge::MergeTrainService) do |svc|
            expect(svc).to receive(:abort).with(
              merge_request,
              a_string_matching(/the merge did not complete in time/),
              hash_including(process_next: false)
            )
          end

          subject

          expect(merge_request).to have_received(:unlock_mr)
          expect(merge_request).to have_received(:add_to_locked_set)
        end
      end
    end

    context 'when pipeline for merge train failed' do
      let(:pipeline) { create(:ci_pipeline, :failed) }

      before do
        merge_request.merge_train_car.update!(pipeline: pipeline)
      end

      it_behaves_like 'drops the merge request from the merge train' do
        let(:expected_reason) do
          'the pipeline did not succeed. ' \
            '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
        end
      end
    end

    context 'when merge request is to be squashed' do
      before do
        merge_request.update!(squash: true)
      end

      let(:pipeline) { create(:ci_pipeline) }

      it_behaves_like 'creates a pipeline for merge train'
    end

    context 'when previous ref is not found' do
      let(:previous_ref) { 'refs/tmp/test' }

      before do
        allow(merge_request.merge_train_car).to receive(:previous_ref) { previous_ref }
      end

      it_behaves_like 'drops the merge request from the merge train' do
        let(:expected_reason) do
          'the previous ref does not exist. ' \
            '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
        end
      end
    end

    context 'when pipeline has not been created yet' do
      let(:pipeline) { create(:ci_pipeline) }

      context 'when the merge request is the first queue' do
        it_behaves_like 'creates a pipeline for merge train'

        context 'when it failed to create a pipeline' do
          before do
            allow_next_instance_of(MergeTrains::CreatePipelineService) do |instance|
              allow(instance).to receive(:execute).and_return({ result: :error, message: 'failed to create pipeline' })
            end
          end

          it_behaves_like 'drops the merge request from the merge train' do
            let(:expected_reason) do
              'the merge train pipeline could not be prepared: failed to create pipeline. ' \
                '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
            end
          end
        end

        context 'when the ref could not be created' do
          before do
            allow_next_instance_of(MergeTrains::CreatePipelineService) do |instance|
              allow(instance).to receive(:execute).and_return(
                { status: :error, message: '9:Failed to create merge commit for source_sha abc and target_sha def.' }
              )
            end
          end

          it_behaves_like 'drops the merge request from the merge train' do
            let(:expected_reason) do
              'the merge train pipeline could not be prepared: ' \
                'Failed to create merge commit for source_sha abc and target_sha def. ' \
                '[Learn more](http://localhost/help/ci/pipelines/merge_trains.md#merge-request-dropped-from-the-merge-train).'
            end
          end
        end
      end
    end

    context 'when pipeline for merge train is running' do
      let(:pipeline) { create(:ci_pipeline, :running, :with_job, project: project, target_sha: previous_ref_sha, source_sha: merge_request.diff_head_sha) }
      let(:previous_ref_sha) { project.repository.commit('refs/heads/master').sha }

      before do
        merge_request.merge_train_car.refresh_pipeline!(pipeline.id)
      end

      context 'when the pipeline is not stale' do
        it_behaves_like 'does not create a pipeline'
      end

      context 'when the pipeline is stale' do
        before do
          merge_request.merge_train_car.update_column(:status, MergeTrains::Car.state_machines[:status].states[:stale].value)
        end

        it_behaves_like 'cancels and recreates a pipeline for the merge train'
      end

      context 'when the pipeline is required to be recreated' do
        let(:require_recreate) { true }

        it_behaves_like 'cancels and recreates a pipeline for the merge train'
      end

      context 'when discussion is added and project is set to only merge if all discussions resolved' do
        before do
          project.update!(only_allow_merge_if_all_discussions_are_resolved: true)
        end

        it 'continues with the current pipeline' do
          create(:discussion_note_on_merge_request, noteable: merge_request, project: project)

          result = subject

          expect(result[:pipeline_created]).to be(false)
          expect(result[:status]).to eq(:success)
          expect(merge_request.merge_status).to eq("can_be_merged")
          expect(merge_request.merge_params).to eq({ "auto_merge_strategy" => "merge_train" })
        end
      end
    end

    context 'when pipeline for merge train succeeded' do
      let(:previous_ref_sha) { project.repository.commit('refs/heads/master').sha }
      let(:pipeline) { create(:ci_pipeline, :success, target_sha: previous_ref_sha, source_sha: merge_request.diff_head_sha) }

      before do
        merge_request.merge_train_car.refresh_pipeline!(pipeline.id)
        merge_request.merge_params['sha'] = merge_request.diff_head_sha
        merge_request.save!
      end

      context 'when a new discussion is added and project only allow merges when all discussions are resolved' do
        before do
          project.update!(only_allow_merge_if_all_discussions_are_resolved: true)
          create(:discussion_note_on_merge_request, noteable: merge_request, project: project)
        end

        it_behaves_like 'merges the merge request'
      end

      context 'when the merge request is the first queue' do
        let(:policy) { create(:scan_result_policy_read, project: project) }

        it_behaves_like 'merges the merge request'

        context 'when a security scan is running' do
          before do
            create(:scan_result_policy_violation, :running, project: project, merge_request: merge_request,
              scan_result_policy_read: policy, violation_data: nil)
          end

          it 'logs that the scan is running' do
            project.update!(merge_method: :ff)
            project.repository.raw_repository.write_ref(merge_request.train_ref_path, pipeline.sha)
            expect(Gitlab::AppLogger).to receive(:warn).with("Security scans running")

            subject
          end
        end

        context 'when no scan is running' do
          before do
            create(:scan_result_policy_violation, :warn, project: project, merge_request: merge_request,
              scan_result_policy_read: policy, violation_data: nil)
          end

          it 'does not log' do
            project.update!(merge_method: :ff)
            project.repository.raw_repository.write_ref(merge_request.train_ref_path, pipeline.sha)
            expect(Gitlab::AppLogger).not_to receive(:warn)

            subject
          end
        end

        using RSpec::Parameterized::TableSyntax

        where(:merge_method) do
          [:ff, :rebase_merge]
        end

        context 'when merge method is standard merge commit' do
          before do
            project.update!(merge_method: :merge)
          end

          context 'when merge_trains_use_train_ref_for_standard_merges is disabled' do
            before do
              stub_feature_flags(merge_trains_use_train_ref_for_standard_merges: false)
            end

            it 'uses the default merge strategy' do
              expect_next_instance_of(
                MergeRequests::MergeService,
                project: project, current_user: maintainer,
                params: instance_of(HashWithIndifferentAccess)
              ) do |service|
                expect(service).to receive(:execute).with(
                  merge_request,
                  skip_discussions_check: true,
                  check_mergeability_retry_lease: true
                ).and_call_original
              end

              subject
            end
          end

          context 'when merge_trains_use_train_ref_for_standard_merges is enabled' do
            before do
              project.repository.raw_repository.write_ref(
                merge_request.train_ref_path, pipeline.sha
              )
            end

            context 'when skip train is allowed' do
              before do
                stub_feature_flags(merge_trains_skip_train: project)
                project.ci_cd_settings.update!(merge_trains_skip_train_allowed: true)
                merge_request.update!(
                  merge_params: merge_request.merge_params.merge(
                    'train_ref' => { 'commit_sha' => pipeline.sha }
                  )
                )
              end

              it 'uses the default merge strategy' do
                expect_next_instance_of(
                  MergeRequests::MergeService,
                  project: project, current_user: maintainer,
                  params: instance_of(HashWithIndifferentAccess)
                ) do |service|
                  expect(service).to receive(:execute).with(
                    merge_request,
                    skip_discussions_check: true,
                    check_mergeability_retry_lease: true
                  )
                end

                subject
              end
            end

            context 'when it is not safe to merge directly from ref' do
              it 'uses the default merge strategy' do
                expect_next_instance_of(
                  MergeRequests::MergeService,
                  project: project, current_user: maintainer,
                  params: instance_of(HashWithIndifferentAccess)
                ) do |service|
                  expect(service).to receive(:execute).with(
                    merge_request,
                    skip_discussions_check: true,
                    check_mergeability_retry_lease: true
                  )
                end

                subject
              end
            end

            context 'when it is safe to merge directly from ref' do
              before do
                merge_request.update!(
                  merge_params: merge_request.merge_params.merge(
                    'train_ref' => { 'commit_sha' => pipeline.sha }
                  )
                )
              end

              it 'uses the FromTrainRef merge strategy', :aggregate_failures do
                expect(merge_request).to receive(:schedule_cleanup_refs).with(only: :train)
                expect(merge_request.merge_train_car).to receive(:start_merge!).and_call_original
                expect(merge_request.merge_train_car).to receive(:finish_merge!).and_call_original
                expect_next_instance_of(
                  MergeRequests::MergeService,
                  project: project, current_user: maintainer,
                  params: instance_of(HashWithIndifferentAccess)
                ) do |service|
                  expect(service).to receive(:execute).with(
                    merge_request,
                    skip_discussions_check: true,
                    check_mergeability_retry_lease: true,
                    merge_strategy: MergeRequests::MergeStrategies::FromTrainRef
                  ).and_call_original
                end

                expect { subject }.to change {
                  merge_request.merge_train_car.status_name
                }.from(:fresh).to(:merged)
                expect(subject[:status]).to eq(:success)
                expect(merge_request.state).to eq("merged")
              end
            end
          end
        end

        with_them do
          before do
            project.update!(merge_method: merge_method)
            project.repository.raw_repository.write_ref(merge_request.train_ref_path, pipeline.sha)
          end

          context 'when it is not safe to merge directly from ref' do
            it 'uses the default merge strategy' do
              expect_next_instance_of(MergeRequests::MergeService, project: project, current_user: maintainer, params: instance_of(HashWithIndifferentAccess)) do |service|
                expect(service).to receive(:execute).with(merge_request, skip_discussions_check: true, check_mergeability_retry_lease: true)
              end

              subject
            end
          end

          context 'when it is safe to merge directly from ref' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge(
                  'train_ref' => {
                    'commit_sha' => pipeline.sha
                  }
                )
              )
            end

            it 'uses the FromTrainRef merge strategy', :aggregate_failures do
              expect(merge_request).to receive(:schedule_cleanup_refs).with(only: :train)
              expect(merge_request.merge_train_car).to receive(:start_merge!).and_call_original
              expect(merge_request.merge_train_car).to receive(:finish_merge!).and_call_original
              expect_next_instance_of(MergeRequests::MergeService, project: project, current_user: maintainer, params: instance_of(HashWithIndifferentAccess)) do |service|
                expect(service).to(
                  receive(:execute).with(
                    merge_request,
                    skip_discussions_check: true,
                    check_mergeability_retry_lease: true,
                    merge_strategy: MergeRequests::MergeStrategies::FromTrainRef
                  ).and_call_original
                )
              end

              expect { subject }.to change { merge_request.merge_train_car.status_name }.from(:fresh).to(:merged)
              expect(subject[:status]).to eq(:success)
              expect(subject[:message]).to be_nil
              expect(merge_request.state).to eq("merged")
            end
          end
        end

        context 'when reconciling an interrupted fast-forward merge' do
          before do
            project.update!(merge_method: :ff)
            project.repository.raw_repository.write_ref(merge_request.train_ref_path, pipeline.sha)
          end

          context 'when the merge_trains_reconcile_silently_merged flag is disabled' do
            before do
              stub_feature_flags(merge_trains_reconcile_silently_merged: false)
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )

              allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
                allow(post_merge).to receive(:execute).and_raise(
                  ActiveRecord::QueryCanceled.new('transient timeout during post-merge')
                )
              end
            end

            it 'does not reconcile and drops the MR from the train (legacy abort)', :aggregate_failures do
              expect_next_instance_of(AutoMerge::MergeTrainService) do |auto_merge|
                expect(auto_merge).to receive(:abort).with(merge_request, anything, hash_including(process_next: false))
              end

              subject

              expect(merge_request.reload).not_to be_merged
            end
          end

          # Regression for gitlab-org/gitlab#598924: ff_merge lands the commit, then a
          # transient error interrupts the post-merge. The MR must be finalised (via
          # PostMergeService), not ejected with the commit left orphaned.
          context 'when a transient error interrupts the post-merge after ff_merge landed the commit' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )
            end

            it 'reconciles the merge through PostMergeService so it is finalised', :aggregate_failures do
              call = 0
              # The post-merge inside MergeService#after_merge fails transiently; the
              # reconcile retry runs a fresh PostMergeService that finalises the merge.
              allow_next_instances_of(MergeRequests::PostMergeService, 2) do |post_merge|
                allow(post_merge).to receive(:execute).and_wrap_original do |original, *args|
                  call += 1
                  raise ActiveRecord::QueryCanceled, 'transient timeout during post-merge' if call == 1

                  original.call(*args)
                end
              end

              car_id = merge_request.merge_train_car.id
              subject

              expect(merge_request.reload).to be_merged
              expect(merge_request.merged_commit_sha).to eq(pipeline.sha)
              expect(merge_request.merged_at).to be_present
              expect(MergeTrains::Car.exists?(car_id)).to be(true)
              expect(merge_request.merge_train_car.status_name).to eq(:merged)
            end
          end

          context 'when the reconciliation itself keeps failing' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )

              # Both the initial post-merge and the reconcile retry fail.
              allow_next_instances_of(MergeRequests::PostMergeService, 2) do |post_merge|
                allow(post_merge).to receive(:execute).and_raise(
                  ActiveRecord::QueryCanceled.new('transient timeout during post-merge')
                )
              end
            end

            it 'raises ReconcileError and preserves the car for a later retry', :aggregate_failures do
              car_id = merge_request.merge_train_car.id

              expect { subject }.to raise_error(described_class::ReconcileError)

              expect(MergeTrains::Car.exists?(car_id)).to be(true)
              expect(merge_request.reload).not_to be_merged
            end
          end

          context 'when the post-merge fails after the MR is already marked merged' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )

              # A later post-merge step times out after mark_as_merged already committed.
              allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
                allow(post_merge).to receive(:execute) do |mr|
                  mr.mark_as_merged
                  raise ActiveRecord::QueryCanceled, 'transient timeout in a later post-merge step'
                end
              end
            end

            it 'finishes the car without aborting the already-merged MR', :aggregate_failures do
              car_id = merge_request.merge_train_car.id

              subject

              expect(merge_request.reload).to be_merged
              expect(MergeTrains::Car.exists?(car_id)).to be(true)
              expect(merge_request.merge_train_car.status_name).to eq(:merged)
            end

            it 'tracks the interrupting error (partial success)' do
              expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
                an_instance_of(ActiveRecord::QueryCanceled),
                hash_including(handler: 'reconcile_interrupted_merge')
              )

              subject
            end
          end

          context 'when the merge attempt raises before landing a commit' do
            # The train ref is the feature head, a real commit ahead of the target, so an
            # unlanded merge leaves it unreachable from the target head. It must match the
            # pipeline sha for merge_from_train_ref? to hold.
            let(:pipeline) do
              create(:ci_pipeline, :success, sha: project.repository.commit('feature').sha,
                target_sha: previous_ref_sha, source_sha: merge_request.diff_head_sha)
            end

            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )
              # A stale but still-reachable merged_commit_sha left by a prior aborted attempt
              # (the target head is trivially reachable from itself). Reconciling on it would
              # wrongly mark the MR merged; only the unlanded train ref sha must qualify.
              merge_request.update_column(
                :merged_commit_sha, project.repository.commit(merge_request.target_branch).sha
              )

              allow_next_instance_of(MergeRequests::MergeService) do |merge_service|
                allow(merge_service).to receive(:execute).and_raise(
                  ActiveRecord::QueryCanceled.new('transient timeout before the merge landed')
                )
              end
            end

            it 'uses the train ref sha, not the stale merged_commit_sha, and drops the MR', :aggregate_failures do
              expect_next_instance_of(AutoMerge::MergeTrainService) do |auto_merge|
                expect(auto_merge).to receive(:abort).with(merge_request, anything, hash_including(process_next: false))
              end

              subject

              expect(merge_request.reload).not_to be_merged
            end
          end

          context 'when MergeService did not persist merged_commit_sha before the interruption' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )
            end

            it 'records the landed train ref sha as merged_commit_sha during the reconcile', :aggregate_failures do
              call = 0
              allow_next_instances_of(MergeRequests::PostMergeService, 2) do |post_merge|
                allow(post_merge).to receive(:execute) do |mr|
                  call += 1
                  if call == 1
                    # The ff commit has landed, but recording merged_commit_sha never happened.
                    mr.update_column(:merged_commit_sha, nil)
                    raise ActiveRecord::QueryCanceled, 'transient timeout during post-merge'
                  end

                  mr.mark_as_merged
                end
              end

              car_id = merge_request.merge_train_car.id
              subject

              expect(merge_request.reload).to be_merged
              # A fresh instance avoids the reader's fallback chain masking the persisted value.
              expect(MergeRequest.find(merge_request.id).read_attribute(:merged_commit_sha)).to eq(pipeline.sha)
              expect(MergeTrains::Car.exists?(car_id)).to be(true)
            end
          end

          context 'when the source branch should be removed on merge' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge(
                  'train_ref' => { 'commit_sha' => pipeline.sha },
                  'should_remove_source_branch' => true
                )
              )
              allow(merge_request).to receive(:can_remove_source_branch?).and_return(true)
            end

            it 'enqueues DeleteSourceBranchWorker during the reconcile', :aggregate_failures do
              call = 0
              allow_next_instances_of(MergeRequests::PostMergeService, 2) do |post_merge|
                allow(post_merge).to receive(:execute) do |mr|
                  call += 1
                  raise ActiveRecord::QueryCanceled, 'transient timeout during post-merge' if call == 1

                  mr.mark_as_merged
                end
              end

              expect(MergeRequests::DeleteSourceBranchWorker).to receive(:perform_async)
                .with(merge_request.id, anything, anything)

              subject

              expect(merge_request.reload).to be_merged
            end

            it 'holds the branch-deletion lease so a concurrent merge into the branch is blocked' do
              allow(MergeRequests::DeleteSourceBranchWorker).to receive(:perform_async)
              call = 0
              allow_next_instances_of(MergeRequests::PostMergeService, 2) do |post_merge|
                allow(post_merge).to receive(:execute) do |mr|
                  call += 1
                  raise ActiveRecord::QueryCanceled, 'transient timeout during post-merge' if call == 1

                  mr.mark_as_merged
                end
              end

              subject

              lease_key = MergeRequests::DeleteSourceBranchWorker.lease_key(
                merge_request.source_project_id, merge_request.source_branch
              )
              # The reconcile holds the lease, so a second attempt to obtain it must fail.
              expect(Gitlab::ExclusiveLease.new(lease_key, timeout: 1.minute).try_obtain).to be_falsey
            end
          end

          context 'when the landing check hits a transient error' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )

              allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
                allow(post_merge).to receive(:execute).and_raise(
                  ActiveRecord::QueryCanceled.new('transient timeout during post-merge')
                )
              end

              # The reachability check itself hits a transient Gitaly error;
              # merge_commit_landed_on_target? rescues it and re-raises as ReconcileError.
              allow(merge_request).to receive(:target_project).and_return(project)
              allow(project.repository).to receive(:ancestor?).and_raise(GRPC::DeadlineExceeded.new('deadline'))
            end

            it 'retries via ReconcileError instead of aborting', :aggregate_failures do
              car_id = merge_request.merge_train_car.id

              expect { subject }.to raise_error(described_class::ReconcileError)

              expect(MergeTrains::Car.exists?(car_id)).to be(true)
              expect(merge_request.reload).not_to be_merged
            end
          end

          context 'when the target branch head cannot be determined (Gitaly returns nil)' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => pipeline.sha })
              )

              allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
                allow(post_merge).to receive(:execute).and_raise(
                  ActiveRecord::QueryCanceled.new('transient timeout during post-merge')
                )
              end

              # Repository#commit swallows a Gitaly failure to nil rather than raising;
              # this must be treated as "don't know" (retry), not "the commit did not land".
              allow(merge_request).to receive(:target_project).and_return(project)
              allow(project.repository).to receive(:commit).and_call_original
              allow(project.repository).to receive(:commit).with(merge_request.target_branch).and_return(nil)
            end

            it 'retries via ReconcileError instead of aborting the car', :aggregate_failures do
              car_id = merge_request.merge_train_car.id

              expect { subject }.to raise_error(described_class::ReconcileError)

              expect(MergeTrains::Car.exists?(car_id)).to be(true)
              expect(merge_request.reload).not_to be_merged
            end
          end

          describe 'which sha counts as landed' do
            before do
              service.instance_variable_set(:@merge_request, merge_request)
            end

            it 'prefers the train ref sha for the FromTrainRef strategy' do
              allow(service).to receive(:merge_from_train_ref?).and_return(true)
              merge_request.update!(
                merge_params: merge_request.merge_params.merge('train_ref' => { 'commit_sha' => 'deadbeef' })
              )

              expect(service.send(:landed_merge_commit_sha)).to eq('deadbeef')
            end

            it 'falls back to merged_commit_sha for non-train-ref strategies' do
              allow(service).to receive(:merge_from_train_ref?).and_return(false)
              merge_request.update_column(:merged_commit_sha, 'abc123def456')

              expect(service.send(:landed_merge_commit_sha)).to eq('abc123def456')
            end
          end

          context 'when the source branch removal is pending and the MR is already merged' do
            before do
              merge_request.update!(
                merge_params: merge_request.merge_params.merge(
                  'train_ref' => { 'commit_sha' => pipeline.sha },
                  'should_remove_source_branch' => true
                )
              )
              allow(merge_request).to receive(:can_remove_source_branch?).and_return(true)

              # PostMergeService marks the MR merged, then a later step fails (window 2).
              allow_next_instance_of(MergeRequests::PostMergeService) do |post_merge|
                allow(post_merge).to receive(:execute) do |mr|
                  mr.mark_as_merged
                  raise ActiveRecord::QueryCanceled, 'transient timeout in a later post-merge step'
                end
              end
            end

            it 'still enqueues DeleteSourceBranchWorker for the already-merged MR', :aggregate_failures do
              expect(MergeRequests::DeleteSourceBranchWorker).to receive(:perform_async)
                .with(merge_request.id, anything, anything)

              subject

              expect(merge_request.reload).to be_merged
            end
          end
        end

        context 'when it failed to merge the merge request' do
          before do
            allow(merge_request).to receive(:broken?).and_return(false)
            merge_request.update!(merge_error: 'Branch has been updated since the merge was requested.')
            allow_next_instance_of(MergeRequests::MergeService) do |instance|
              allow(instance).to receive(:execute).and_return({ result: :error })
            end
          end

          it 'does not finish merge and drops the merge request from train' do
            expect(merge_request).to be_on_train
            expect(merge_request.merge_train_car).to receive(:start_merge!).and_call_original
            expect(merge_request.merge_train_car).not_to receive(:finish_merge!)

            subject

            expect(merge_request.reload).not_to be_on_train
          end

          it_behaves_like 'drops the merge request from the merge train' do
            let(:expected_reason) do
              'the merge could not be completed. Branch has been updated since the merge was requested.'
            end
          end
        end
      end

      context 'when the merge request is not the first queue' do
        before do
          allow(merge_request.merge_train_car).to receive(:effectively_first_car?).and_return(false)
        end

        it 'does not merge the merge request' do
          expect(MergeRequests::MergeService).not_to receive(:new)

          subject
        end
      end
    end
  end
end
