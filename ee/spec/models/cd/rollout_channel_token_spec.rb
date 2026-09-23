# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::RolloutChannelToken, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }

  describe 'factory' do
    it 'creates a valid rollout channel token using factory defaults' do
      expect(create(:cd_rollout_channel_token)).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:rollout).required }
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to belong_to(:rollout_step).optional }
  end

  describe 'sharding key' do
    subject { build(:cd_rollout_channel_token, rollout: rollout) }

    it { is_expected.to populate_sharding_key(:organization_id).with(rollout.organization_id) }
  end

  describe 'validations' do
    subject { build(:cd_rollout_channel_token, rollout: rollout) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:channel_name) }
    it { is_expected.to validate_presence_of(:token) }

    it 'rejects a channel_name over 255 bytes' do
      token = build(:cd_rollout_channel_token, rollout: rollout, channel_name: 'a' * 256)

      expect(token).not_to be_valid
      expect(token.errors[:channel_name]).to be_present
    end

    it 'accepts a channel_name at exactly 255 bytes' do
      token = build(:cd_rollout_channel_token, rollout: rollout, channel_name: 'a' * 255)

      expect(token).to be_valid
    end

    it 'rejects a token over 4096 bytes' do
      token = build(:cd_rollout_channel_token, rollout: rollout, token: 'a' * 4097)

      expect(token).not_to be_valid
      expect(token.errors[:token]).to be_present
    end

    it 'accepts a token at exactly 4096 bytes' do
      token = build(:cd_rollout_channel_token, rollout: rollout, token: 'a' * 4096)

      expect(token).to be_valid
    end

    it 'counts multi-byte channel_name characters by bytesize, not length' do
      # 128 multi-byte characters are 128 chars long but 256 bytes (2 bytes each in UTF-8)
      token = build(:cd_rollout_channel_token, rollout: rollout, channel_name: 'é' * 128)

      expect(token).not_to be_valid
      expect(token.errors[:channel_name]).to be_present
    end

    it 'rejects a non-string token' do
      token = build(:cd_rollout_channel_token, rollout: rollout, token: { foo: 'bar' })

      expect(token).not_to be_valid
      expect(token.errors[:token]).to include('must be a string')
    end

    it 'validates uniqueness of channel_name scoped to rollout' do
      create(:cd_rollout_channel_token, rollout: rollout, channel_name: 'approval-1')

      duplicate = build(:cd_rollout_channel_token, rollout: rollout, channel_name: 'approval-1')

      expect(duplicate).not_to be_valid
    end

    it 'allows the same channel_name across different rollouts' do
      other_rollout = create(:cd_rollout)
      create(:cd_rollout_channel_token, rollout: rollout, channel_name: 'approval-1')

      other = build(:cd_rollout_channel_token, rollout: other_rollout, channel_name: 'approval-1')

      expect(other).to be_valid
    end

    it 'enforces uniqueness of (rollout_id, channel_name) at the database level' do
      create(:cd_rollout_channel_token, rollout: rollout, channel_name: 'approval-1')

      duplicate = build(:cd_rollout_channel_token, rollout: rollout, channel_name: 'approval-1',
        organization: rollout.organization)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'encryption' do
    it 'stores the token encrypted at rest' do
      secret = SecureRandom.hex(16)
      record = create(:cd_rollout_channel_token, rollout: rollout, token: secret)

      expect(record.token).to eq(secret)
      expect(record.ciphertext_for(:token)).not_to include(secret)
    end
  end

  describe 'serialization' do
    it 'excludes token from serializable_hash' do
      record = create(:cd_rollout_channel_token, rollout: rollout, token: SecureRandom.hex(16))

      expect(record.serializable_hash).not_to have_key('token')
    end

    it 'excludes token from as_json' do
      record = create(:cd_rollout_channel_token, rollout: rollout, token: SecureRandom.hex(16))

      expect(record.as_json).not_to have_key('token')
    end

    it 'excludes token from inspect' do
      secret = SecureRandom.hex(16)
      record = create(:cd_rollout_channel_token, rollout: rollout, token: secret)

      expect(record.inspect).not_to include(secret)
    end
  end

  describe '.upsert_token!' do
    let(:step) { create(:cd_rollout_step, rollout: rollout, path: '0.1') }

    it 'creates a new token with the given rollout_step' do
      token = described_class.upsert_token!(
        rollout: rollout, channel_name: 'approval-1', token: 'a-token', rollout_step: step
      )

      expect(token).to have_attributes(channel_name: 'approval-1', token: 'a-token', rollout_step: step)
    end

    it 'defaults rollout_step to nil when not given' do
      token = described_class.upsert_token!(rollout: rollout, channel_name: 'approval-1', token: 'a-token')

      expect(token.rollout_step).to be_nil
    end

    it 'overwrites the rollout_step on a re-post of the same channel_name' do
      described_class.upsert_token!(rollout: rollout, channel_name: 'approval-1', token: 'a-token', rollout_step: step)

      other_step = create(:cd_rollout_step, rollout: rollout, path: '0.2')
      updated = described_class.upsert_token!(
        rollout: rollout, channel_name: 'approval-1', token: 'a-new-token', rollout_step: other_step
      )

      expect(updated.rollout_step).to eq(other_step)
    end
  end

  describe 'foreign keys' do
    it 'is deleted when its rollout is destroyed' do
      token = create(:cd_rollout_channel_token, rollout: rollout)

      rollout.destroy!

      expect(described_class.exists?(token.id)).to be(false)
    end

    it 'is deleted when its organization is destroyed' do
      other_organization = create(:organization)
      other_application = create(:cd_application, organization: other_organization)
      other_version_set = create(:cd_version_set, application: other_application)
      other_rollout = create(:cd_rollout, version_set: other_version_set)
      token = create(:cd_rollout_channel_token, rollout: other_rollout)

      other_organization.destroy!

      expect(described_class.exists?(token.id)).to be(false)
    end

    it 'keeps the token, with rollout_step nulled out, when its step is destroyed' do
      step = create(:cd_rollout_step, rollout: rollout, path: '0.1')
      token = create(:cd_rollout_channel_token, rollout: rollout, rollout_step: step)

      step.destroy!

      expect(token.reload.rollout_step).to be_nil
    end
  end
end
