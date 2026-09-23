# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCredits::Backoff, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  def ttl_of(key)
    Gitlab::Redis::SharedState.with { |redis| redis.ttl(key) }
  end

  # Redis TTLs run on the wall clock, so stand in for a latch expiring.
  def expire_latch
    Gitlab::Redis::SharedState.with { |redis| redis.del(described_class::LATCH_KEY) }
  end

  # Wide enough for a stalled runner, narrow enough to tell the doubling bands apart.
  def be_about(duration)
    be_between(duration.to_i - 30, duration.to_i)
  end

  it 'is inactive until triggered' do
    expect(described_class.active?).to be(false)
  end

  it 'is active and records the reason after a trigger, and is inactive once cleared' do
    described_class.trigger!(reason: :server_error)

    expect(described_class.active?).to be(true)
    expect(described_class.reason).to eq(:server_error)

    described_class.clear!

    expect(described_class.active?).to be(false)
    expect(described_class.reason).to be_nil
  end

  it 'treats a Redis failure as inactive instead of raising' do
    allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(::Redis::CannotConnectError)

    expect(Gitlab::ErrorTracking).to receive(:track_exception).twice

    expect { described_class.trigger!(reason: :connection_error) }.not_to raise_error
    expect(described_class.active?).to be(false)
  end

  it 'swallows redis-client errors the same way' do
    allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(::RedisClient::ConnectionError)

    expect(Gitlab::ErrorTracking).to receive(:track_exception).once

    expect { described_class.record_failure(reason: :server_error, source: 'a') }.not_to raise_error
  end

  it 'expires after the short duration for a degradation signal' do
    described_class.trigger!(reason: :connection_error)

    expect(ttl_of(described_class::LATCH_KEY)).to be_between(1, described_class::BACKOFF_DURATION.to_i)
  end

  it 'holds for hours when CustomersDot has switched the field off' do
    described_class.trigger!(reason: :disabled)

    ttl = ttl_of(described_class::LATCH_KEY)

    expect(ttl).to be > described_class::BACKOFF_DURATION.to_i
    expect(ttl).to be <= described_class::DISABLED_BACKOFF_DURATION.to_i
  end

  describe '.trigger!' do
    it 'doubles the degradation latch on each consecutive trip, up to the cap' do
      [30.minutes, 1.hour, 2.hours, 4.hours, 4.hours].each do |duration|
        described_class.trigger!(reason: :server_error)

        expect(ttl_of(described_class::LATCH_KEY)).to be_about(duration)

        expire_latch
      end
    end

    it 'neither escalates nor shortens a latch that is still running' do
      described_class.trigger!(reason: :server_error)
      expire_latch
      described_class.trigger!(reason: :connection_error)

      described_class.trigger!(reason: :server_error)

      expect(ttl_of(described_class::LATCH_KEY)).to be_about(1.hour)
      expect(described_class.reason).to eq(:connection_error)
    end

    it 'neither shortens nor relabels a running kill-switch latch on a degradation failure' do
      described_class.trigger!(reason: :disabled)

      described_class.trigger!(reason: :server_error)

      expect(described_class.reason).to eq(:disabled)
      expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::DISABLED_BACKOFF_DURATION)
    end

    it 'keeps at least the base window after a failure late in a running latch' do
      described_class.trigger!(reason: :server_error)
      Gitlab::Redis::SharedState.with { |redis| redis.expire(described_class::LATCH_KEY, 60) }

      described_class.trigger!(reason: :server_error)

      expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::BACKOFF_DURATION)
    end

    it 'keeps the streak for the quiet period past the latch' do
      described_class.trigger!(reason: :server_error)

      expect(ttl_of(described_class::STREAK_KEY))
        .to be_about(described_class::BACKOFF_DURATION + described_class::STREAK_QUIET_PERIOD)
    end

    it 'holds the kill switch for its fixed duration and never counts it towards escalation' do
      2.times do
        described_class.trigger!(reason: :disabled)

        expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::DISABLED_BACKOFF_DURATION)

        expire_latch
      end

      described_class.trigger!(reason: :server_error)

      expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::BACKOFF_DURATION)
    end

    it 'lets the kill switch take over a running degradation latch' do
      described_class.trigger!(reason: :server_error)

      described_class.trigger!(reason: :disabled)

      expect(described_class.reason).to eq(:disabled)
      expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::DISABLED_BACKOFF_DURATION)
    end
  end

  describe '.retry_floor' do
    it 'is nil when not latched' do
      expect(described_class.retry_floor).to be_nil
    end

    it 'is the time left on a degradation latch' do
      described_class.trigger!(reason: :server_error)

      expect(described_class.retry_floor).to be_about(described_class::BACKOFF_DURATION)
    end

    it 'is nil under the kill switch, so batches keep probing for the field coming back' do
      described_class.trigger!(reason: :disabled)

      expect(described_class.retry_floor).to be_nil
    end

    it 'is nil when Redis is unavailable' do
      allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(::Redis::CannotConnectError)
      allow(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(described_class.retry_floor).to be_nil
    end
  end

  describe '.clear!' do
    it 'forgets the escalation along with the latch' do
      described_class.trigger!(reason: :server_error)
      described_class.clear!

      described_class.trigger!(reason: :server_error)

      expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::BACKOFF_DURATION)
    end
  end

  describe '.record_failure', :freeze_time do
    it 'latches on first sight of the kill switch' do
      described_class.record_failure(reason: :disabled, source: 'a')

      expect(described_class.reason).to eq(:disabled)
    end

    it 'does not latch while one source keeps failing, however many times' do
      5.times { described_class.record_failure(reason: :server_error, source: 'same-source') }

      expect(described_class.active?).to be(false)
    end

    it 'latches once enough distinct sources fail inside the window' do
      sources = Array.new(described_class::FAILURE_THRESHOLD) { |i| "source-#{i}" }
      sources[0...-1].each { |source| described_class.record_failure(reason: :server_error, source: source) }

      expect(described_class.active?).to be(false)

      described_class.record_failure(reason: :server_error, source: sources.last)

      expect(described_class.reason).to eq(:server_error)
    end

    it 'counts sources per fixed window, so one failing source per tick never accumulates' do
      window = described_class::FAILURE_WINDOW.to_i
      travel_to(Time.zone.at((((Time.current.to_i / window) + 1) * window) - 60))

      described_class.record_failure(reason: :server_error, source: 'a')
      described_class.record_failure(reason: :server_error, source: 'b')
      travel 2.minutes
      described_class.record_failure(reason: :server_error, source: 'c')

      expect(described_class.active?).to be(false)
    end

    it 'forgets failures after the window' do
      described_class.record_failure(reason: :connection_error, source: 'a')

      expect(ttl_of(described_class.send(:failures_key))).to be_between(1, described_class::FAILURE_WINDOW.to_i)
    end
  end

  describe '.record_success', :freeze_time do
    it 'does not reset the count, so a partially failing CustomersDot still latches' do
      described_class.record_failure(reason: :server_error, source: 'a')
      described_class.record_failure(reason: :server_error, source: 'b')
      described_class.record_success
      described_class.record_failure(reason: :server_error, source: 'c')

      expect(described_class.reason).to eq(:server_error)
    end

    it 'lifts a kill-switch latch, since the field is evidently back on' do
      described_class.trigger!(reason: :disabled)
      described_class.record_success

      expect(described_class.active?).to be(false)
    end

    it 'leaves a degradation latch to run out its window, so a partial recovery cannot flap the cron' do
      described_class.trigger!(reason: :server_error)
      described_class.record_success

      expect(described_class.reason).to eq(:server_error)
    end

    it 'resets the escalation, since CustomersDot is serving requests again' do
      described_class.trigger!(reason: :server_error)
      expire_latch
      described_class.record_success

      described_class.trigger!(reason: :server_error)

      expect(ttl_of(described_class::LATCH_KEY)).to be_about(described_class::BACKOFF_DURATION)
    end
  end
end
