# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Scans::PurgeWorker, feature_category: :vulnerability_management do
  include ExclusiveLeaseHelpers

  let(:worker) { described_class.new }
  let(:lease_key) { described_class.name.underscore }
  let!(:lease) { stub_exclusive_lease(lease_key, timeout: described_class::LEASE_TTL) }

  def result(status, updated_count: 0)
    ::Security::PurgeScansService::Result.new(status: status, updated_count: updated_count)
  end

  describe '#perform' do
    subject(:perform) { worker.perform }

    before do
      allow(::Security::PurgeScansService).to receive(:purge_stale_records).and_return(result(:drained))
    end

    it 'delegates the call to PurgeScansService' do
      perform

      expect(::Security::PurgeScansService).to have_received(:purge_stale_records)
    end

    describe 'exclusive lease' do
      it 'runs the purge while holding the lease' do
        expect(lease).to receive(:try_obtain).and_return('uuid')

        perform

        expect(::Security::PurgeScansService).to have_received(:purge_stale_records)
      end

      it 'releases the lease after a successful run' do
        expect(lease).to receive(:cancel)

        perform
      end

      it 'releases the lease even when the purge raises' do
        allow(::Security::PurgeScansService).to receive(:purge_stale_records).and_raise(RuntimeError, 'boom')

        expect(lease).to receive(:cancel)

        expect { perform }.to raise_error(RuntimeError, 'boom')
      end

      context 'when the lease is already held' do
        before do
          stub_exclusive_lease_taken(lease_key)
        end

        it 'no-ops without running the purge' do
          perform

          expect(::Security::PurgeScansService).not_to have_received(:purge_stale_records)
        end

        it 'does not re-enqueue' do
          expect(described_class).not_to receive(:perform_in)

          perform
        end

        it 'logs that it was skipped' do
          expect(Gitlab::AppLogger).to receive(:info).with(
            hash_including(message: a_string_including('exclusive lease'))
          )

          perform
        end
      end
    end

    describe 'self re-enqueue' do
      context 'when work remains and the database is healthy' do
        before do
          allow(::Security::PurgeScansService)
            .to receive(:purge_stale_records).and_return(result(:work_remaining, updated_count: 200_000))
        end

        it 're-enqueues to continue draining from the cursor' do
          expect(described_class).to receive(:perform_in).with(described_class::RE_ENQUEUE_DELAY)

          perform
        end
      end

      context 'when the stale set is drained' do
        before do
          allow(::Security::PurgeScansService).to receive(:purge_stale_records).and_return(result(:drained))
        end

        it 'does not re-enqueue' do
          expect(described_class).not_to receive(:perform_in)

          perform
        end
      end

      context 'when the pre-run health gate tripped (unhealthy)' do
        before do
          allow(::Security::PurgeScansService).to receive(:purge_stale_records).and_return(result(:unhealthy))
        end

        it 'does not re-enqueue' do
          expect(described_class).not_to receive(:perform_in)

          perform
        end
      end

      context 'when a health hard-stop halted the run mid-flight' do
        before do
          allow(::Security::PurgeScansService)
            .to receive(:purge_stale_records).and_return(result(:halted, updated_count: 5))
        end

        it 'does not re-enqueue' do
          expect(described_class).not_to receive(:perform_in)

          perform
        end
      end
    end
  end
end
