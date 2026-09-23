# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::TaskClaimExpiredEventWorker, :zoekt_settings_enabled,
  feature_category: :global_search do
  let(:event) { Search::Zoekt::TaskClaimExpiredEvent.build }

  let_it_be_with_reload(:expired_tasks) do
    create_list(:zoekt_task, 3, state: :processing, claimed_until: 1.hour.ago)
  end

  let_it_be_with_reload(:live_task) { create(:zoekt_task, state: :processing, claimed_until: 1.hour.from_now) }

  it_behaves_like 'subscribes to event'

  it_behaves_like 'an idempotent worker' do
    it 'releases expired claims and leaves live ones held' do
      expect(Gitlab::EventStore).not_to receive(:publish).with(
        an_object_having_attributes(class: Search::Zoekt::TaskClaimExpiredEvent)
      )

      consume_event(subscriber: described_class, event: event)

      expect(expired_tasks.map(&:reload)).to all(be_pending)
      expect(live_task.reload).to be_processing
    end
  end

  context 'when there are more expired claims than the batch size' do
    before do
      stub_const("#{Search::Zoekt::Taskable}::EXPIRED_CLAIM_BATCH_SIZE", 2)
    end

    it 'processes only up to the batch size and schedules another event' do
      expect(Gitlab::EventStore).to receive(:publish).with(
        an_object_having_attributes(class: Search::Zoekt::TaskClaimExpiredEvent)
      )

      expect { consume_event(subscriber: described_class, event: event) }
        .to change { Search::Zoekt::Task.with_expired_claim.count }.by(-2)
    end

    context 'and a node callback settled one row of the batch concurrently' do
      # A settled row is selected but not mutated, so the re-publish signal has
      # to read the selected count or the remaining backlog waits 10 minutes.
      before do
        allow(Search::Zoekt::Task).to receive(:reset_expired_claims!).and_return(selected: 2, reaped: 1)
      end

      it 'still schedules another event and logs only the rows it reaped' do
        expect(Gitlab::EventStore).to receive(:publish).with(
          an_object_having_attributes(class: Search::Zoekt::TaskClaimExpiredEvent)
        )

        worker = described_class.new
        expect(worker).to receive(:log_extra_metadata_on_done).with(:tasks_with_expired_claim_count, 1)

        worker.handle_event(event)
      end
    end
  end
end
