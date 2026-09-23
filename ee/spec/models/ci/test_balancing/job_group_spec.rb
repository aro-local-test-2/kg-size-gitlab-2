# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TestBalancing::JobGroup, feature_category: :code_testing do
  subject(:job_group) { build(:ci_test_balancing_job_group) }

  it { is_expected.to be_valid }

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  it_behaves_like 'cleanup by a loose foreign key' do
    let!(:parent) { create(:project) }
    let!(:model) { create(:ci_test_balancing_job_group, project: parent) }
  end

  describe '.find_or_create!', :freeze_time do
    let_it_be(:project) { create(:project) }

    let(:name) { 'rspec unit' }

    subject(:result) { described_class.find_or_create!(project.id, name) }

    context 'when the group does not exist' do
      it 'creates a persisted group with a fresh last_seen_at' do
        expect { result }.to change { described_class.count }.by(1)

        expect(result).to be_persisted
        expect(result.name).to eq(name)
        expect(result.last_seen_at).to be_within(1.minute).of(Time.current)
      end
    end

    context 'when the group already exists' do
      let_it_be_with_reload(:existing) do
        create(:ci_test_balancing_job_group, project: project, name: 'rspec unit')
      end

      it 'returns the existing group without creating a duplicate' do
        expect { result }.not_to change { described_class.count }
        expect(result.id).to eq(existing.id)
      end

      it 'refreshes last_seen_at when it is older than the throttle window' do
        existing.update_column(:last_seen_at, (Ci::TestBalancing::LAST_SEEN_THROTTLE_INTERVAL + 1.hour).ago)

        result

        expect(existing.reload.last_seen_at).to be_like_time(Time.current)
      end

      it 'does not rewrite last_seen_at within the throttle window' do
        existing.update_column(:last_seen_at, 1.hour.ago)

        expect { result }.not_to change { existing.reload.last_seen_at }
      end

      it 'recovers when a concurrent insert wins the race' do
        # First lookup misses (as if the row did not exist yet), so create! runs
        # and hits the unique index the concurrent node already populated. The
        # rescue's find_by! then falls through to the real lookup.
        call_count = 0
        allow(described_class).to receive(:find_by).and_wrap_original do |original, *args|
          call_count += 1
          call_count == 1 ? nil : original.call(*args)
        end

        expect { result }.not_to raise_error
        expect(result.id).to eq(existing.id)
      end
    end
  end

  describe '#touch_last_seen!', :freeze_time do
    let_it_be(:group, reload: true) { create(:ci_test_balancing_job_group) }

    it 'updates last_seen_at when older than the throttle window' do
      group.update_column(:last_seen_at, (Ci::TestBalancing::LAST_SEEN_THROTTLE_INTERVAL + 1.hour).ago)

      group.touch_last_seen!

      expect(group.reload.last_seen_at).to be_like_time(Time.current)
    end

    it 'is a no-op within the throttle window' do
      group.update_column(:last_seen_at, 1.hour.ago)

      expect { group.touch_last_seen! }
        .not_to change { group.reload.last_seen_at }
    end
  end
end
