# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Rollouts::PruneIncomingEventsWorker, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }

  describe '#perform' do
    it 'deletes events older than the cutoff regardless of status' do
      old_pending = create(:cd_rollout_incoming_event, rollout: rollout, created_at: 61.days.ago)
      old_completed = create(:cd_rollout_incoming_event, rollout: rollout, created_at: 61.days.ago, status: :completed)
      recent = create(:cd_rollout_incoming_event, rollout: rollout, created_at: 1.day.ago)

      described_class.new.perform

      expect(Cd::RolloutIncomingEvent.all).to contain_exactly(recent)
      expect(Cd::RolloutIncomingEvent.exists?(old_pending.id)).to be(false)
      expect(Cd::RolloutIncomingEvent.exists?(old_completed.id)).to be(false)
    end

    it 'does nothing when there are no old events' do
      recent = create(:cd_rollout_incoming_event, rollout: rollout, created_at: 1.day.ago)

      described_class.new.perform

      expect(Cd::RolloutIncomingEvent.all).to contain_exactly(recent)
    end

    it 'drains more than one batch of old events' do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      old_events = create_list(:cd_rollout_incoming_event, 5, rollout: rollout, created_at: 61.days.ago)

      described_class.new.perform

      expect(Cd::RolloutIncomingEvent.where(id: old_events.map(&:id))).to be_none
    end
  end
end
