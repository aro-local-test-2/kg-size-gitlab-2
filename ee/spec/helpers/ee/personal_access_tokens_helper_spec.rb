# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::PersonalAccessTokensHelper, feature_category: :system_access do
  let(:instance_level_max_personal_access_token_lifetime) { nil }
  let(:user) { build(:user) }

  before do
    allow(helper).to receive(:current_user) { user }
    stub_application_setting(max_personal_access_token_lifetime: instance_level_max_personal_access_token_lifetime)
  end

  describe '#personal_access_token_expiration_policy_enabled?' do
    subject { helper.personal_access_token_expiration_policy_enabled? }

    context 'with `personal_access_token_expiration_policy` licensed' do
      before do
        stub_licensed_features(personal_access_token_expiration_policy: true)
      end

      context 'the instance has an expiry setting' do
        let(:instance_level_max_personal_access_token_lifetime) { 20 }

        it { is_expected.to be_truthy }
      end

      context 'the instance does not have an expiry setting' do
        it { is_expected.to be_falsey }
      end
    end

    context 'with `personal_access_token_expiration_policy` not licensed' do
      before do
        stub_licensed_features(personal_access_token_expiration_policy: false)
      end

      context 'the instance has an expiry setting' do
        let(:instance_level_max_personal_access_token_lifetime) { 20 }

        it { is_expected.to be_falsey }
      end

      context 'the instance does not have an expiry setting' do
        it { is_expected.to be_falsey }
      end
    end
  end

  describe '#personal_access_token_max_expiry_date', :freeze_time do
    subject { helper.personal_access_token_max_expiry_date }

    context 'the instance has an expiry setting' do
      let(:instance_level_max_personal_access_token_lifetime) { 20 }

      it { is_expected.to eq(Date.current + 20.days) }
    end

    context 'the instance does not have an expiry setting' do
      it { is_expected.to be_nil }
    end
  end

  describe '#personal_access_token_max_expiry_days' do
    subject { helper.personal_access_token_max_expiry_days }

    context 'the instance has an expiry setting' do
      let(:instance_level_max_personal_access_token_lifetime) { 20 }

      it { is_expected.to eq(20) }
    end

    context 'the instance does not have an expiry setting' do
      it { is_expected.to be_nil }
    end
  end

  shared_examples 'feature availability' do
    context 'when feature is licensed' do
      before do
        stub_licensed_features(feature => true)
      end

      it { is_expected.to be_truthy }
    end

    context 'with `personal_access_token_expiration_policy` not licensed' do
      before do
        stub_licensed_features(feature => false)
      end

      it { is_expected.to be_falsey }
    end
  end

  describe '#personal_access_token_expiration_policy_licensed?' do
    subject { helper.personal_access_token_expiration_policy_licensed? }

    let(:feature) { :personal_access_token_expiration_policy }

    it_behaves_like 'feature availability'
  end

  describe '#max_personal_access_token_lifetime_in_days' do
    subject { helper.max_personal_access_token_lifetime_in_days }

    context 'when `buffered_token_expiration_limit` feature flag is enabled' do
      it { is_expected.to eq(400) }
    end

    context 'when `buffered_token_expiration_limit` feature flag is disabled' do
      before do
        stub_feature_flags(buffered_token_expiration_limit: false)
      end

      it { is_expected.to eq(365) }
    end
  end
end
