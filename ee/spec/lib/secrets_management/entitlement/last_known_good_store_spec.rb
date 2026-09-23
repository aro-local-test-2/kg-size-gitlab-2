# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::Entitlement::LastKnownGoodStore,
  :clean_gitlab_redis_shared_state, feature_category: :secrets_management do
  let(:key) { [:secrets_management_entitlement, :saas, 42] }

  let(:trial) do
    ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
      state: :trial,
      trial_started_at: Time.zone.parse('2026-09-01T00:00:00Z'),
      trial_expires_at: Time.zone.parse('2026-10-01T00:00:00Z'),
      credits_remaining: 12.5,
      credits_total: 500.0,
      on_demand_enabled: true
    )
  end

  let(:resolve) do
    ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
  end

  describe '.write and .read' do
    it 'round-trips both responses' do
      described_class.write(key, trial: trial, resolve: resolve)

      record = described_class.read(key)

      expect(record.trial).to eq(trial)
      expect(record.resolve).to eq(resolve)
    end

    # Symbols and Times survive only because the cache store's coder handles
    # them; a plain JSON round-trip would hand back strings and the response
    # constructors would reject them.
    it 'preserves value types rather than stringifying them', :aggregate_failures do
      described_class.write(key, trial: trial, resolve: resolve)

      record = described_class.read(key)

      expect(record.trial.state).to eq(:trial)
      expect(record.trial.trial_expires_at).to eq(trial.trial_expires_at)
      expect(record.trial.credits_remaining).to eq(12.5)
      expect(record.trial.on_demand_enabled).to be true
    end

    it 'stamps resolved_at at write time', :freeze_time do
      described_class.write(key, trial: trial, resolve: resolve)

      expect(described_class.read(key).resolved_at).to eq(Time.current)
    end

    it 'round-trips a blocked resolve with its reason' do
      blocked = ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
        blocked: true, blocked_reason: :no_billable_source_error
      )

      described_class.write(key, trial: trial, resolve: blocked)

      expect(described_class.read(key).resolve.blocked_reason).to eq(:no_billable_source_error)
    end

    it 'keys per namespace' do
      described_class.write(key, trial: trial, resolve: resolve)

      expect(described_class.read([:secrets_management_entitlement, :saas, 99])).to be_nil
    end
  end

  describe '.read' do
    it 'returns nil when nothing was written' do
      expect(described_class.read(key)).to be_nil
    end

    it 'returns nil once the window has elapsed' do
      described_class.write(key, trial: trial, resolve: resolve)

      travel_to(described_class::WINDOW.from_now + 1.minute) do
        expect(described_class.read(key)).to be_nil
      end
    end

    it 'still reads a slot written just inside the window' do
      described_class.write(key, trial: trial, resolve: resolve)

      travel_to(described_class::WINDOW.from_now - 1.minute) do
        expect(described_class.read(key)).not_to be_nil
      end
    end

    context 'when the stored payload no longer matches the response classes' do
      def store_raw(payload)
        described_class.send(:cache_store).write(key, payload)
      end

      it 'ignores a field the class no longer declares' do
        store_raw(
          trial: trial.to_h.merge(a_field_since_removed: 'x'),
          resolve: resolve.to_h,
          resolved_at: Time.current
        )

        expect(described_class.read(key).trial).to eq(trial)
      end

      it 'returns nil when a required field is absent' do
        store_raw(trial: trial.to_h.except(:state), resolve: resolve.to_h, resolved_at: Time.current)

        expect(described_class.read(key)).to be_nil
      end

      it 'returns nil when the payload is not a hash' do
        store_raw('not a hash')

        expect(described_class.read(key)).to be_nil
      end
    end
  end

  describe '.delete' do
    it 'removes the slot' do
      described_class.write(key, trial: trial, resolve: resolve)

      described_class.delete(key)

      expect(described_class.read(key)).to be_nil
    end
  end

  # `ActiveSupport::Cache::RedisCacheStore` wraps every read and write in a failsafe that already
  # rescues `Redis::BaseError`, `ConnectionPool::Error` and `ConnectionPool::TimeoutError`. Pin that
  # here: a Redis fault must never deny an entitled customer.
  describe 'a failing redis server' do
    # A bare object, not a verifying double: the cache store calls
    # `redis.then { |c| c.set(...) }`, and a double rejects `then`.
    let(:failing_connection) do
      Class.new do
        def initialize(error)
          @error = error
        end

        def set(*, **)
          raise @error
        end
        alias_method :get, :set
        alias_method :del, :set
      end
    end

    before do
      allow(described_class.send(:cache_store))
        .to receive(:redis).and_return(failing_connection.new(error))
    end

    [
      Redis::CannotConnectError.new('Error connecting to Redis'),
      Redis::TimeoutError.new('Connection timed out'),
      Redis::OutOfMemoryError.new("OOM command not allowed when used memory > 'maxmemory'"),
      ConnectionPool::TimeoutError.new('Waited 1 sec')
    ].each do |redis_error|
      context "when it raises #{redis_error.class}" do
        let(:error) { redis_error }

        it 'is swallowed by every method', :aggregate_failures do
          expect { described_class.write(key, trial: trial, resolve: resolve) }.not_to raise_error
          expect { described_class.read(key) }.not_to raise_error
          expect { described_class.delete(key) }.not_to raise_error
        end
      end
    end

    # Control: proves all three methods really reach the seam the failsafe wraps. Without it, a
    # rename of `redis` upstream would leave every example above passing vacuously.
    context 'when it raises a class the failsafe does not rescue' do
      let(:error) { ArgumentError.new('boom') }

      it 'propagates out of every method', :aggregate_failures do
        expect { described_class.write(key, trial: trial, resolve: resolve) }.to raise_error(ArgumentError)
        expect { described_class.read(key) }.to raise_error(ArgumentError)
        expect { described_class.delete(key) }.to raise_error(ArgumentError)
      end
    end
  end
end
