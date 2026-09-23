# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TestBalancing::ClaimService, :clean_gitlab_redis_shared_state, feature_category: :code_testing do
  let_it_be(:pipeline) { create(:ci_pipeline) }

  let_it_be(:node_total) { 3 }

  let_it_be(:build) do
    create(:ci_build, pipeline: pipeline, name: 'rspec unit 1/3',
      options: { instance: 1, parallel: { total: node_total } })
  end

  let_it_be(:job_group) do
    create(:ci_test_balancing_job_group, project: pipeline.project, name: 'rspec unit')
  end

  let_it_be(:test_a) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/a_spec.rb') }
  let_it_be(:test_b) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/b_spec.rb') }
  let_it_be(:test_c) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/c_spec.rb') }
  let_it_be(:test_d) { create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/d_spec.rb') }

  let(:queue) do
    Ci::TestBalancing::Queue.new(
      pipeline_id: pipeline.id,
      job_group_id: job_group.id,
      node_index: 1,
      node_total: node_total
    )
  end

  subject(:execute) { described_class.new(build).execute }

  before do
    stub_licensed_features(ci_parallel_test_balancing: true)
  end

  describe '#execute' do
    context 'when the project does not have the required license' do
      before do
        stub_licensed_features(ci_parallel_test_balancing: false)
      end

      it 'returns a feature_unavailable error' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:feature_unavailable)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(parallel_test_balancing: false)
      end

      it 'returns a feature_unavailable error' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:feature_unavailable)
      end
    end

    context 'when the job is not a parallel job' do
      let(:build) do
        create(:ci_build, pipeline: pipeline, name: 'rspec unit', options: {})
      end

      it 'returns a not_parallel error' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:not_parallel)
      end
    end

    context 'when the job is a matrix job' do
      let(:build) do
        create(:ci_build, pipeline: pipeline, name: 'rspec unit: [ruby]',
          options: { instance: 1, parallel: { matrix: [{ RUBY: 'ruby' }], total: node_total } })
      end

      it 'returns a not_parallel error' do
        expect(execute).to be_error
        expect(execute.reason).to eq(:not_parallel)
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

    context 'when the job group was never seeded' do
      it 'returns an empty batch' do
        expect(execute.payload[:test_splits]).to eq([])
      end
    end

    context 'with pending tests' do
      before do
        queue.seed([
          { test_split_id: test_a.id, expected_duration: 500.0 },
          { test_split_id: test_b.id, expected_duration: 400.0 },
          { test_split_id: test_c.id, expected_duration: 100.0 },
          { test_split_id: test_d.id, expected_duration: 50.0 }
        ])
      end

      # budget = clamp(1050 / 3, 120, 600) = 350.
      it 'claims the slowest tests within the budget', :aggregate_failures do
        tests = execute.payload[:test_splits]

        expect(tests.map { |t| t[:path] }).to eq([test_a.path])
        expect(tests.first[:expected_duration]).to eq(500.0)
        expect(queue.size).to eq(3)
      end

      it 'persists a write-once assignment per claimed test', :aggregate_failures do
        test_splits = execute.payload[:test_splits]

        assignments = Ci::TestBalancing::Assignment.where(node_index: 1)
        expect(assignments.count).to eq(test_splits.size)
        expect(assignments.map(&:pipeline_id)).to all(eq(pipeline.id))
        expect(assignments.map(&:expected_duration)).to match_array(test_splits.map { |t| t[:expected_duration] })
      end

      it 'clears the node backup after persisting' do
        execute

        expect(queue.backup).to eq([])
      end

      it 'never claims the same test twice across nodes', :aggregate_failures do
        first_batch = execute.payload[:test_splits].map { |t| t[:path] }

        other_node = create(:ci_build, pipeline: pipeline, name: 'rspec unit 3/3',
          options: { instance: 3, parallel: { total: node_total } })
        second_batch = described_class.new(other_node).execute.payload[:test_splits].map { |t| t[:path] }

        expect(first_batch & second_batch).to be_empty
      end
    end

    context 'when a prior claim left an unconfirmed backup' do
      before do
        # Simulate a claim that popped into the backup but crashed before the PG write
        queue.seed([{ test_split_id: test_a.id, expected_duration: 42.0 }])
        queue.claim

        # Extra pending test
        queue.seed([{ test_split_id: test_b.id, expected_duration: 100.0 }])
      end

      it 'recovers the backup instead of claiming new work', :aggregate_failures do
        tests = execute.payload[:test_splits]

        expect(tests).to eq([{ path: test_a.path, expected_duration: 42.0 }])
        expect(queue.backup).to eq([])
        expect(Ci::TestBalancing::Assignment.where(node_index: 1).count).to eq(1)
      end
    end

    context 'when the pool is smaller than the budget' do
      before do
        queue.seed([
          { test_split_id: test_a.id, expected_duration: 1.0 },
          { test_split_id: test_b.id, expected_duration: 2.0 }
        ])
      end

      it 'claims everything in one batch' do
        expect(execute.payload[:test_splits].size).to eq(2)
        expect(queue.size).to eq(0)
      end
    end
  end
end
