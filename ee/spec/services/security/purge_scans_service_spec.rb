# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::PurgeScansService, feature_category: :vulnerability_management do
  describe 'class interface' do
    describe '.purge_stale_records', :clean_gitlab_redis_shared_state do
      let!(:stale_scan) { create(:security_scan, created_at: 92.days.ago) }
      let(:stale_scan_tuple_cache) do
        { "created_at" => Security::Scan.connection.quote(stale_scan.created_at), "id" => stale_scan.id }
      end

      let!(:fresh_scan) { create(:security_scan) }

      subject(:purge_stale_records) { described_class.purge_stale_records }

      it 'instantiates the service class with stale scans' do
        expect { purge_stale_records }.to change { stale_scan.reload.status }.to("purged")
                                      .and not_change { fresh_scan.reload.status }
      end

      it 'returns a drained result when no stale work remains' do
        expect(purge_stale_records.status).to eq(:drained)
      end

      describe 'database health gating' do
        let(:normal_signal) do
          instance_double(Gitlab::Database::HealthStatus::Signals::Normal, stop?: false)
        end

        let(:stop_signal) do
          instance_double(Gitlab::Database::HealthStatus::Signals::Stop, stop?: true)
        end

        context 'when the health check feature flag is disabled' do
          before do
            stub_feature_flags(security_scans_purge_db_health_check: false)
          end

          it 'does not evaluate database health and purges as before' do
            expect(Gitlab::Database::HealthStatus).not_to receive(:evaluate)

            expect { purge_stale_records }.to change { stale_scan.reload.status }.to("purged")
          end
        end

        context 'when the health check feature flag is enabled' do
          before do
            stub_feature_flags(security_scans_purge_db_health_check: true)
          end

          context 'when the database is healthy' do
            before do
              allow(Gitlab::Database::HealthStatus).to receive(:evaluate).and_return([normal_signal])
            end

            it 'proceeds and purges stale scans' do
              expect { purge_stale_records }.to change { stale_scan.reload.status }.to("purged")
            end
          end

          context 'when the database is unhealthy before the run starts' do
            before do
              allow(Gitlab::Database::HealthStatus).to receive(:evaluate).and_return([stop_signal])
            end

            it 'backs off and does not purge stale scans' do
              expect { purge_stale_records }.not_to change { stale_scan.reload.status }
            end

            it 'does not run the purge query' do
              expect(described_class).not_to receive(:execute)

              purge_stale_records
            end

            it 'returns an unhealthy result' do
              expect(purge_stale_records.status).to eq(:unhealthy)
            end
          end
        end
      end

      describe 'dead tuple optimisation' do
        let(:redis_key) { "CursorStore:#{described_class::LAST_PURGED_SCAN_TUPLE}" }

        def cached_tuple
          data_on_redis = Gitlab::Redis::SharedState.with { |redis| redis.get(redis_key) }

          Gitlab::Json.parse(data_on_redis)
        end

        it 'caches a previous purged tuple' do
          expect { purge_stale_records }.to change {
            cached_tuple
          }.from(nil).to(stale_scan_tuple_cache)
        end

        context 'when a previous purged tuple is cached' do
          let!(:second_stale_scan) { create(:security_scan, created_at: 91.days.ago) }

          before do
            Gitlab::Redis::SharedState.with do |redis|
              redis.set(redis_key, stale_scan_tuple_cache.to_json)
            end
          end

          it 'uses the cached tuple to scope the query and skip already checked values' do
            expect { purge_stale_records }.to change { second_stale_scan.reload.status }.to("purged")
                                          .and not_change { stale_scan.reload.status }
          end
        end
      end
    end

    describe '.purge_by_build_ids' do
      let(:security_scans) { create_list(:security_scan, 2) }

      subject(:purge_by_build_ids) { described_class.purge_by_build_ids([security_scans.first.build_id]) }

      it 'instantiates the service class with scans by given build ids' do
        expect { purge_by_build_ids }.to change { security_scans.first.reload.status }.to("purged")
                                     .and not_change { security_scans.second.reload.status }
      end
    end
  end

  describe '#execute', :clean_gitlab_redis_shared_state do
    let!(:stale_scans) do
      create_list(:security_scan, 3, created_at: 92.days.ago)
    end

    let(:scope) { Security::Scan.stale.ordered_by_created_at_and_id }

    subject(:execute) { described_class.new(scope).execute }

    describe 'bounded runtime' do
      before do
        # Isolate the runtime bound from health modulation: with the flag off the run uses a
        # fixed batch size (feature flags default on in tests, which would otherwise shrink it).
        stub_feature_flags(security_scans_purge_db_health_check: false)
      end

      it 'stops when MAX_RUNTIME is exceeded and reports remaining work' do
        # Trip the runtime limiter after the first batch so the run breaks with work left.
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end

        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)

        result = execute

        expect(result.status).to eq(:work_remaining)
        expect(result.updated_count).to eq(1)
      end

      it 'persists the cursor before breaking on the runtime bound' do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end

        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)

        expect { execute }.to change { described_class.redis_cursor.cursor }.from({})
      end
    end

    describe 'count cap' do
      before do
        stub_feature_flags(security_scans_purge_db_health_check: false)
      end

      it 'stops when MAX_STALE_SCANS_SIZE is reached and reports remaining work' do
        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)
        stub_const("#{described_class}::MAX_STALE_SCANS_SIZE", 1)

        result = execute

        expect(result.status).to eq(:work_remaining)
        expect(result.updated_count).to eq(1)
      end
    end

    describe 'drain detection' do
      it 'reports drained when the whole stale set is purged' do
        result = execute

        expect(result.status).to eq(:drained)
        expect(result.updated_count).to eq(3)
      end
    end

    describe 'health modulation while running' do
      # Use real signal objects: the run policy distinguishes them by class
      # (Signals::Normal vs other), so instance doubles would not satisfy is_a?.
      let(:normal_signal) do
        Gitlab::Database::HealthStatus::Signals::Normal.new(:indicator, reason: 'healthy')
      end

      let(:stop_signal) do
        Gitlab::Database::HealthStatus::Signals::Stop.new(:indicator, reason: 'stop')
      end

      let(:moderate_signal) do
        Gitlab::Database::HealthStatus::Signals::NotAvailable.new(:indicator, reason: 'no signal')
      end

      before do
        stub_feature_flags(security_scans_purge_db_health_check: true)
        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)
        stub_const("#{described_class}::MIN_BATCH_SIZE", 1)
        stub_const("#{described_class}::HEALTH_CHECK_INTERVAL", 1)
      end

      it 'hard-stops mid-run, persists the cursor, and reports halted' do
        allow(described_class).to receive(:evaluate_health).and_return([stop_signal])

        result = nil
        expect { result = execute }.to change { described_class.redis_cursor.cursor }.from({})

        expect(result.status).to eq(:halted)
        # Only the first batch is purged before the mid-run hard stop breaks the loop.
        expect(result.updated_count).to eq(1)
        expect(stale_scans.map { |s| s.reload.status }).to include("created")
      end

      it 'shrinks the batch size and sleeps under moderate pressure' do
        allow(described_class).to receive(:evaluate_health).and_return([moderate_signal])

        service = described_class.new(scope)
        expect(service).to receive(:sleep).with(described_class::MODERATE_PRESSURE_SLEEP).at_least(:once)

        service.execute

        expect(service.instance_variable_get(:@batch_size)).to eq(described_class::MIN_BATCH_SIZE)
      end

      it 'uses the full batch size and does not sleep when healthy' do
        allow(described_class).to receive(:evaluate_health).and_return([normal_signal])

        service = described_class.new(scope)
        expect(service).not_to receive(:sleep)

        service.execute

        expect(service.instance_variable_get(:@batch_size)).to eq(described_class::MAX_BATCH_SIZE)
      end
    end

    describe 'flag-off parity' do
      before do
        stub_feature_flags(security_scans_purge_db_health_check: false)
        stub_const("#{described_class}::MAX_BATCH_SIZE", 1)
      end

      it 'never evaluates health and never sleeps' do
        expect(described_class).not_to receive(:evaluate_health)

        service = described_class.new(scope)
        expect(service).not_to receive(:sleep)

        result = service.execute

        expect(result.updated_count).to eq(3)
        expect(service.instance_variable_get(:@batch_size)).to eq(described_class::MAX_BATCH_SIZE)
      end
    end
  end

  describe described_class::Result do
    it 're_enqueue? is true only for work_remaining' do
      expect(described_class.new(status: :work_remaining, updated_count: 1).re_enqueue?).to be(true)
      expect(described_class.new(status: :drained, updated_count: 1).re_enqueue?).to be(false)
      expect(described_class.new(status: :halted, updated_count: 1).re_enqueue?).to be(false)
      expect(described_class.new(status: :unhealthy, updated_count: 0).re_enqueue?).to be(false)
    end
  end
end
