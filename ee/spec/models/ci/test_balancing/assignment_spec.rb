# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TestBalancing::Assignment, feature_category: :code_testing do
  subject(:assignment) { build(:ci_test_balancing_assignment) }

  it { is_expected.to be_valid }

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:pipeline).class_name('Ci::Pipeline') }
    it { is_expected.to belong_to(:test_split).class_name('Ci::TestBalancing::TestSplit') }
    it { is_expected.to belong_to(:job_group).class_name('Ci::TestBalancing::JobGroup') }
  end

  describe 'partitioning' do
    it 'uses daily partitions retained for 30 days' do
      expect(described_class.partitioning_strategy).to be_a(Gitlab::Database::Partitioning::Time::DailyStrategy)
      expect(described_class.partitioning_strategy.retain_for).to eq(30.days)
    end
  end

  describe '.test_splits_for_node' do
    let_it_be(:pipeline) { create(:ci_pipeline) }
    let_it_be(:job_group) { create(:ci_test_balancing_job_group, project: pipeline.project) }

    let_it_be(:slow_test_split) do
      create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/slow_spec.rb')
    end

    let_it_be(:fast_test_split) do
      create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/fast_spec.rb')
    end

    let_it_be(:slow) do
      create(:ci_test_balancing_assignment, project: pipeline.project, pipeline: pipeline,
        job_group: job_group, test_split: slow_test_split, expected_duration: 100.0, node_index: 1)
    end

    let_it_be(:fast) do
      create(:ci_test_balancing_assignment, project: pipeline.project, pipeline: pipeline,
        job_group: job_group, test_split: fast_test_split, expected_duration: 10.0, node_index: 1)
    end

    subject(:result) { described_class.test_splits_for_node(pipeline, job_group, 1) }

    it 'returns the tests for the node as path/duration hashes, slowest first' do
      expect(result).to eq([
        { path: 'spec/slow_spec.rb', expected_duration: 100.0 },
        { path: 'spec/fast_spec.rb', expected_duration: 10.0 }
      ])
    end

    it 'excludes rows for a different node' do
      other_test_split = create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/other_spec.rb')
      create(:ci_test_balancing_assignment, project: pipeline.project, pipeline: pipeline,
        job_group: job_group, test_split: other_test_split, expected_duration: 50.0, node_index: 2)

      expect(result.map { |t| t[:path] }).to contain_exactly('spec/slow_spec.rb', 'spec/fast_spec.rb')
    end

    it 'excludes rows for a different job group' do
      other_group = create(:ci_test_balancing_job_group, project: pipeline.project, name: 'rspec other')
      other_test_split = create(:ci_test_balancing_test_split, project: pipeline.project, path: 'spec/other_spec.rb')
      create(:ci_test_balancing_assignment, project: pipeline.project, pipeline: pipeline,
        job_group: other_group, test_split: other_test_split, expected_duration: 50.0, node_index: 1)

      expect(result.map { |t| t[:path] }).to contain_exactly('spec/slow_spec.rb', 'spec/fast_spec.rb')
    end
  end
end
