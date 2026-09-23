# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::ThrottledErrorTracking, feature_category: :secrets_management do
  describe '.track_exception' do
    let(:error) { ActiveRecord::StatementInvalid.new('connection lost') }

    # A method rather than a subject: every example here calls it more than once,
    # and a memoized subject would only run the first.
    def track(**overrides)
      described_class.track_exception(
        error, **{ throttle_key: :entitlement_fail_closed, gl_namespace_id: 7 }.merge(overrides)
      )
    end

    context 'with a real cache store', :use_clean_rails_memory_store_caching do
      it 'reports the first occurrence to Sentry', :aggregate_failures do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, { gl_namespace_id: 7 })
        expect(::Gitlab::ErrorTracking).not_to receive(:log_exception)

        track
      end

      it 'logs later occurrences in the window instead of reporting them', :aggregate_failures do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).once
        expect(::Gitlab::ErrorTracking).to receive(:log_exception).twice.with(error, { gl_namespace_id: 7 })

        3.times { track }
      end

      it 'reports again once the window has passed' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

        track
        travel_to((described_class::REPORT_TTL + 1.minute).from_now) { track }
      end

      it 'honours a caller-supplied ttl' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

        track(ttl: 1.hour)
        travel_to(61.minutes.from_now) { track(ttl: 1.hour) }
      end

      it 'does not mask a different error class raised in the same window' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

        track
        described_class.track_exception(Timeout::Error.new('timed out'), throttle_key: :entitlement_fail_closed)
      end

      it 'throttles each call site independently' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

        track
        track(throttle_key: :secrets_read_emitter)
      end

      it 'keys on the whole throttle_key, so a composite key throttles per component' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

        track(throttle_key: [:unmapped_block_reason, :on_demand_disabled])
        track(throttle_key: [:unmapped_block_reason, :usage_not_allowed])
      end
    end

    context 'when the cache cannot hold the window' do
      it 'reports every occurrence rather than suppressing, when the write does not persist' do
        allow(Rails.cache).to receive_messages(exist?: false, write: false)

        expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

        2.times { track }
      end

      it 'reports rather than raising, when the cache raises', :aggregate_failures do
        allow(Rails.cache).to receive(:exist?).and_raise(Redis::CannotConnectError)

        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, { gl_namespace_id: 7 })

        expect { track }.not_to raise_error
      end
    end
  end
end
