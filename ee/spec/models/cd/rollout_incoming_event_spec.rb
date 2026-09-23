# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::RolloutIncomingEvent, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }

  describe 'factory' do
    it 'creates a valid rollout incoming event using factory defaults' do
      expect(create(:cd_rollout_incoming_event)).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:rollout).required }
    it { is_expected.to belong_to(:organization).required }
  end

  describe 'sharding key' do
    subject { build(:cd_rollout_incoming_event, rollout: rollout) }

    it { is_expected.to populate_sharding_key(:organization_id).with(rollout.organization_id) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, completed: 1) }
  end

  describe 'validations' do
    subject { build(:cd_rollout_incoming_event, rollout: rollout) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:idempotency_key) }

    it 'rejects an idempotency_key over 255 bytes' do
      event = build(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'a' * 256)

      expect(event).not_to be_valid
      expect(event.errors[:idempotency_key]).to be_present
    end

    it 'accepts an idempotency_key at exactly 255 bytes' do
      event = build(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'a' * 255)

      expect(event).to be_valid
    end

    it 'validates uniqueness of idempotency_key scoped to rollout' do
      create(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'event-1')

      duplicate = build(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'event-1')

      expect(duplicate).not_to be_valid
    end

    it 'allows the same idempotency_key across different rollouts' do
      other_rollout = create(:cd_rollout)
      create(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'event-1')

      other = build(:cd_rollout_incoming_event, rollout: other_rollout, idempotency_key: 'event-1')

      expect(other).to be_valid
    end

    it 'enforces uniqueness of (rollout_id, idempotency_key) at the database level' do
      create(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'event-1')

      duplicate = build(:cd_rollout_incoming_event, rollout: rollout, idempotency_key: 'event-1',
        organization: rollout.organization)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'foreign keys' do
    it 'is deleted when its rollout is destroyed' do
      event = create(:cd_rollout_incoming_event, rollout: rollout)

      rollout.destroy!

      expect(described_class.exists?(event.id)).to be(false)
    end

    it 'is deleted when its organization is destroyed' do
      other_organization = create(:organization)
      other_application = create(:cd_application, organization: other_organization)
      other_version_set = create(:cd_version_set, application: other_application)
      other_rollout = create(:cd_rollout, version_set: other_version_set)
      event = create(:cd_rollout_incoming_event, rollout: other_rollout)

      other_organization.destroy!

      expect(described_class.exists?(event.id)).to be(false)
    end
  end
end
