# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::Integration, feature_category: :compliance_management do
  subject(:integration) { build(:ai_compliance_anthropic_integration) }

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).class_name('::Group').required }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:api_key) }
    it { is_expected.to validate_length_of(:api_key).is_at_most(510) }
    it { is_expected.to validate_length_of(:anthropic_organization_uuid).is_at_most(255) }
    it { is_expected.to validate_length_of(:list_cursor).is_at_most(2048) }
    it { is_expected.to validate_length_of(:last_error).is_at_most(1024) }

    it 'allows only one integration per namespace' do
      existing = create(:ai_compliance_anthropic_integration)
      duplicate = build(:ai_compliance_anthropic_integration, namespace: existing.namespace)

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:namespace_id]).to include('has already been taken')
    end

    context 'when the namespace is a subgroup' do
      it 'is invalid' do
        integration.namespace = build(:group, :nested)

        expect(integration).to be_invalid
        expect(integration.errors[:namespace]).to include('must be a top-level group.')
      end
    end

    context 'when the namespace is a top-level group' do
      it { is_expected.to be_valid }
    end
  end

  describe 'defaults' do
    it 'starts disabled, with no failures and no disabled reason' do
      expect(integration.enabled).to be(false)
      expect(integration.consecutive_failure_count).to eq(0)
      expect(integration.disabled_reason).to be_nil
    end

    it 'has never synced' do
      expect(integration.last_successful_sync_at).to be_nil
    end
  end

  describe 'disabled_reason' do
    it 'defines the reasons GitLab can disable the integration itself' do
      expect(described_class.disabled_reasons.keys)
        .to contain_exactly('invalid_key', 'local_sessions_unavailable', 'repeated_failures')
    end

    it 'round-trips a reason' do
      integration.disabled_reason = :invalid_key
      integration.save!

      expect(integration.reload.disabled_reason).to eq('invalid_key')
      expect(integration).to be_disabled_reason_invalid_key
    end
  end

  describe 'api_key encryption' do
    it 'does not persist the key in plaintext' do
      integration.save!

      ciphertext = described_class.connection.select_value(
        "SELECT api_key FROM #{described_class.table_name} WHERE id = #{integration.id}"
      )

      expect(ciphertext).not_to include('sk-ant-api01-test-key')
      expect(integration.reload.api_key).to eq('sk-ant-api01-test-key')
    end
  end
end
