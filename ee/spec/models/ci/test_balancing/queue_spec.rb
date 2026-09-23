# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TestBalancing::Queue, :clean_gitlab_redis_shared_state, feature_category: :code_testing do
  let(:pipeline_id) { 42 }
  let(:job_group_id) { 7 }
  let(:node_total) { 3 }

  subject(:queue) { queue_for(1) }

  def queue_for(node_index, node_total: self.node_total)
    described_class.new(
      pipeline_id: pipeline_id,
      job_group_id: job_group_id,
      node_index: node_index,
      node_total: node_total
    )
  end

  def sum_key
    "test_balancing:{#{pipeline_id}:#{job_group_id}}:sum"
  end

  def queue_key
    "test_balancing:{#{pipeline_id}:#{job_group_id}}:queue"
  end

  def redis_sum
    Gitlab::Redis::SharedState.with { |r| r.get(sum_key).to_f }
  end

  def redis_ttl(key)
    Gitlab::Redis::SharedState.with { |r| r.ttl(key) }
  end

  describe '#seed' do
    it 'adds items scored by duration and tracks the running sum' do
      queue.seed([
        { test_split_id: 1, expected_duration: 100.0 },
        { test_split_id: 2, expected_duration: 50.0 }
      ])

      expect(queue.backup).to eq([])
      expect(redis_sum).to eq(150.0)
    end

    it 'is idempotent and does not double-count re-seeded items' do
      queue.seed([{ test_split_id: 1, expected_duration: 100.0 }])
      queue.seed([
        { test_split_id: 1, expected_duration: 100.0 },
        { test_split_id: 2, expected_duration: 50.0 }
      ])

      expect(redis_sum).to eq(150.0)
    end

    it 'sets a TTL on the queue and sum keys' do
      queue.seed([{ test_split_id: 1, expected_duration: 100.0 }])

      expect(redis_ttl(queue_key)).to be > 0
      expect(redis_ttl(sum_key)).to be > 0
    end

    it 'returns early for an empty list' do
      expect(queue.seed([])).to eq(0)
      expect(redis_sum).to eq(0.0)
    end

    it 'returns the added sum with its fractional part intact' do
      expect(queue.seed([{ test_split_id: 1, expected_duration: 33.45 }])).to eq(33.45)
      expect(redis_sum).to eq(33.45)
    end

    it 'falls back to the default duration when expected_duration is nil' do
      queue.seed([{ test_split_id: 1, expected_duration: nil }])

      expect(queue.backup).to eq([])
      expect(redis_sum).to eq(described_class::DEFAULT_DURATION)
      expect(queue_for(1, node_total: 1).claim)
        .to eq([{ test_split_id: 1, expected_duration: described_class::DEFAULT_DURATION }])
    end
  end

  describe '#claim' do
    before do
      queue.seed([
        { test_split_id: 1, expected_duration: 300.0 },
        { test_split_id: 2, expected_duration: 200.0 },
        { test_split_id: 3, expected_duration: 100.0 },
        { test_split_id: 4, expected_duration: 50.0 }
      ])
    end

    it 'claims the slowest items first while under the budget' do
      # budget = clamp(650 / 1, 120, 600) = 600
      claimed = queue_for(1, node_total: 1).claim

      expected_claims = [
        { test_split_id: 1, expected_duration: 300.0 },
        { test_split_id: 2, expected_duration: 200.0 },
        { test_split_id: 3, expected_duration: 100.0 }
      ]

      expect(claimed).to eq(expected_claims)
      expect(queue.backup).to eq(expected_claims)
      expect(redis_sum).to eq(50.0)
    end

    it 'claims at least one item even when it is over the budget' do
      # budget = clamp(650 / 3, 120, 600) = 216.7
      claimed = queue.claim

      expected_claims = [
        { test_split_id: 1, expected_duration: 300.0 }
      ]

      expect(claimed).to eq(expected_claims)
      expect(queue.backup).to eq(expected_claims)
      expect(redis_sum).to eq(350.0)
    end

    it 'never hands the same test to two nodes' do
      first = queue_for(1).claim
      second = queue_for(2).claim

      first_ids = first.map { |t| t[:test_split_id] }
      second_ids = second.map { |t| t[:test_split_id] }

      expect(first_ids & second_ids).to be_empty
    end

    it 'drains the queue over successive claims' do
      all = []
      10.times do
        batch = queue.claim
        break if batch.empty?

        all.concat(batch)
      end

      expect(all.map { |t| t[:test_split_id] }).to match_array([1, 2, 3, 4])
      expect(redis_sum).to eq(0.0)
    end

    it 'preserves fractional durations' do
      queue.seed([{ test_split_id: 9, expected_duration: 1233.45 }])

      claimed = queue.claim

      expected_claims = [
        { test_split_id: 9, expected_duration: 1233.45 }
      ]

      expect(claimed).to eq(expected_claims)
      expect(queue.backup).to eq(expected_claims)
    end
  end

  describe '#claim item cap' do
    it 'caps a claim at MAX_CLAIM_ITEMS even when the budget would allow more' do
      count = described_class::MAX_CLAIM_ITEMS + 20
      queue.seed(Array.new(count) { |i| { test_split_id: 100 + i, expected_duration: 0.1 } })

      claimed = queue_for(1, node_total: 1).claim

      expect(claimed.size).to eq(described_class::MAX_CLAIM_ITEMS)
    end
  end

  describe '#backup and #clear_backup' do
    before do
      queue.seed([{ test_split_id: 1, expected_duration: 500.0 }])
      queue.claim
    end

    it 'reads the node backup' do
      expect(queue.backup).to eq([{ test_split_id: 1, expected_duration: 500.0 }])
    end

    it 'clears the node backup' do
      queue.clear_backup

      expect(queue.backup).to eq([])
    end

    it 'scopes backups per node' do
      expect(queue_for(2).backup).to eq([])
    end
  end
end
