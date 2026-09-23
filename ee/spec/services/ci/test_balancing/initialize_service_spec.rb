# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TestBalancing::InitializeService, :clean_gitlab_redis_shared_state, feature_category: :code_testing do
  let_it_be(:pipeline) { create(:ci_pipeline) }

  let_it_be(:node_index) { 1 }
  let_it_be(:node_total) { 3 }

  let_it_be(:build) do
    create(:ci_build, pipeline: pipeline, name: 'rspec unit 1/3',
      options: { instance: node_index, parallel: { total: node_total } })
  end

  let(:test_splits) do
    [
      { path: 'spec/models/a_spec.rb', expected_duration: 10.5 },
      { path: 'spec/models/b_spec.rb', expected_duration: 5.0 },
      { path: 'spec/models/c_spec.rb', expected_duration: nil }
    ]
  end

  subject(:execute) { described_class.new(build).execute(test_splits) }

  before do
    stub_licensed_features(ci_parallel_test_balancing: true)
  end

  def queue_for(job)
    job_group = Ci::TestBalancing::JobGroup.find_by(
      project_id: pipeline.project_id, name: ::Gitlab::Utils::Job.group_name(job.name)
    )

    Ci::TestBalancing::Queue.new(
      pipeline_id: pipeline.id,
      job_group_id: job_group.id,
      node_index: node_index,
      node_total: node_total
    )
  end

  describe '#execute' do
    context 'when the project does not have the required license' do
      before do
        stub_licensed_features(ci_parallel_test_balancing: false)
      end

      it 'returns a feature_unavailable error without seeding', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:feature_unavailable)
        expect(Ci::TestBalancing::TestSplit.count).to eq(0)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(parallel_test_balancing: false)
      end

      it 'returns a feature_unavailable error without seeding', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:feature_unavailable)
        expect(Ci::TestBalancing::TestSplit.count).to eq(0)
      end
    end

    context 'when the job is not a parallel job' do
      let(:build) do
        create(:ci_build, pipeline: pipeline, name: 'rspec unit', options: {})
      end

      it 'returns a not_parallel error without seeding', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:not_parallel)
        expect(Ci::TestBalancing::TestSplit.count).to eq(0)
      end
    end

    context 'when the job is a matrix job' do
      let(:build) do
        create(:ci_build, pipeline: pipeline, name: 'rspec unit: [ruby]',
          options: { instance: node_index, parallel: { matrix: [{ RUBY: 'ruby' }], total: node_total } })
      end

      it 'returns a not_parallel error without seeding', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:not_parallel)
        expect(Ci::TestBalancing::TestSplit.count).to eq(0)
      end
    end

    context 'when the pipeline is older than the retention period' do
      it 'returns a retention_expired error', :aggregate_failures do
        travel_to(pipeline.created_at + Ci::TestBalancing::Assignment::RETENTION_PERIOD + 1.day) do
          expect(execute).to be_error
          expect(execute.reason).to eq(:retention_expired)
        end
      end
    end

    context 'when a test path is invalid' do
      let(:test_splits) { [{ path: 'valid' }, { path: 'a' * 1025, expected_duration: 1.0 }] }

      it 'returns an invalid_tests error without seeding', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:invalid_tests)
        expect(Ci::TestBalancing::TestSplit.count).to eq(0)
      end
    end

    context 'when seeding would exceed the per-job-group limit' do
      before do
        stub_const("::Ci::TestBalancing::MAX_TEST_SPLITS_PER_JOB_GROUP", 2)
      end

      let(:test_splits) do
        [
          { path: 'spec/a_spec.rb', expected_duration: 1.0 },
          { path: 'spec/b_spec.rb', expected_duration: 1.0 },
          { path: 'spec/c_spec.rb', expected_duration: 1.0 }
        ]
      end

      it 'returns an invalid_tests error without seeding', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:invalid_tests)
        expect(execute.message).to include('exceeds the limit')

        expect(Ci::TestBalancing::TestSplit.count).to eq(0)
        expect(queue_for(build).size).to eq(0)
      end
    end

    context 'when the node has no claimed tests (seed path)' do
      it 'persists the job group name without the parallel suffix' do
        execute

        expect(Ci::TestBalancing::JobGroup.pluck(:name)).to eq(['rspec unit'])
      end

      it 'persists the test split paths' do
        execute

        expect(Ci::TestBalancing::TestSplit.pluck(:path)).to match_array(test_splits.map { |t| t[:path] })
      end

      it 'seeds the Redis queue' do
        execute

        expect(queue_for(build).size).to eq(test_splits.size)
      end

      it 'returns an empty replay set' do
        expect(execute.payload[:test_splits_to_replay]).to eq([])
      end

      it 'is idempotent across re-seeds', :aggregate_failures do
        described_class.new(build).execute(test_splits)

        expect { execute }
          .to not_change { Ci::TestBalancing::TestSplit.count }
          .and not_change { Ci::TestBalancing::JobGroup.count }
      end

      it 'keeps job groups separate per job name' do
        other_group_node = create(:ci_build, pipeline: pipeline, name: 'rspec integration 1/2',
          options: { instance: 1, parallel: { total: 2 } })
        other_group_test_splits = test_splits.first(2)

        execute
        described_class.new(other_group_node).execute(other_group_test_splits)

        expect(Ci::TestBalancing::JobGroup.count).to eq(2)
        expect(Ci::TestBalancing::TestSplit.count).to eq(3)

        expect(queue_for(build).size).to eq(test_splits.size)
        expect(queue_for(other_group_node).size).to eq(other_group_test_splits.size)
      end
    end

    context 'when the node already has claimed tests (retry path)' do
      let_it_be(:job_group) do
        create(:ci_test_balancing_job_group, project: pipeline.project, name: 'rspec unit')
      end

      let_it_be(:test_a) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/a_spec.rb') }
      let_it_be(:test_b) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/b_spec.rb') }

      before do
        [[test_a, 10.0], [test_b, 5.0]].each do |test_split, duration|
          create(:ci_test_balancing_assignment, project: pipeline.project, pipeline: pipeline,
            job_group: job_group, test_split: test_split, expected_duration: duration, node_index: 1)
        end
      end

      it 'replays the committed tests for this node, slowest first', :aggregate_failures do
        replayed = execute.payload[:test_splits_to_replay]

        expect(replayed.map { |t| t[:path] }).to eq(['spec/a_spec.rb', 'spec/b_spec.rb'])
        expect(replayed.map { |t| t[:expected_duration] }).to eq([10.0, 5.0])
      end

      it 'does not seed the queue' do
        expect { execute }.not_to change { queue_for(build).size }
      end
    end

    context 'when the node has an unconfirmed backup (crash recovery)' do
      let_it_be(:job_group) do
        create(:ci_test_balancing_job_group, project: pipeline.project, name: 'rspec unit')
      end

      let_it_be(:test_a) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/a_spec.rb') }

      before do
        # Simulate a claim that popped into the backup but crashed before the PG write
        queue = queue_for(build)
        queue.seed([{ test_split_id: test_a.id, expected_duration: 42.0 }])
        queue.claim
      end

      it 'recovers the backup into a durable assignment and returns it', :aggregate_failures do
        replayed = execute.payload[:test_splits_to_replay]

        expect(replayed).to eq([{ path: 'spec/a_spec.rb', expected_duration: 42.0 }])
      end

      context 'when the node also has committed claims' do
        let_it_be(:committed_test) do
          create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/committed_spec.rb')
        end

        before do
          create(:ci_test_balancing_assignment, project: pipeline.project, pipeline: pipeline,
            job_group: job_group, test_split: committed_test, expected_duration: 100.0, node_index: node_index)
        end

        it 'returns the union of committed and recovered tests, slowest first', :aggregate_failures do
          replayed = execute.payload[:test_splits_to_replay]

          expect(replayed).to eq([
            { path: 'spec/committed_spec.rb', expected_duration: 100.0 },
            { path: 'spec/a_spec.rb', expected_duration: 42.0 }
          ])
        end
      end
    end
  end
end
