# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::InstanceEnrollment, feature_category: :secrets_management do
  describe '.enrolled?' do
    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.enrolled?).to be true
      end
    end

    context 'when instance is not enrolled' do
      it 'returns false' do
        expect(described_class.enrolled?).to be false
      end
    end
  end

  describe '.beta?' do
    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.beta?).to be true
      end
    end

    context 'when instance is not enrolled' do
      it 'returns false' do
        expect(described_class.beta?).to be false
      end
    end
  end

  describe '.beta_enrolled?' do
    context 'when the instance is enrolled' do
      it 'returns true when the beta marker is set' do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: true
        )

        expect(described_class.beta_enrolled?).to be true
      end

      it 'returns false when the beta marker is not set' do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: false
        )

        expect(described_class.beta_enrolled?).to be false
      end

      # Pins the derivation to `.beta?` so a future GA marker only has to
      # be added there.
      it 'returns false when the instance is enrolled but no longer in beta' do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_beta_enrolled: true
        )
        allow(described_class).to receive(:beta?).and_return(false)

        expect(described_class.beta_enrolled?).to be false
      end
    end

    context 'when the instance is not enrolled' do
      it 'returns false even when a stale beta marker is set' do
        stub_application_setting(
          secrets_manager_instance_enrolled: false,
          secrets_manager_instance_beta_enrolled: true
        )

        expect(described_class.beta_enrolled?).to be false
      end
    end
  end

  describe '.add_on_requested?' do
    context 'when the instance is enrolled and the add-on intent is stamped' do
      before do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_add_on_requested_at: 1.day.ago
        )
      end

      it 'returns true' do
        expect(described_class.add_on_requested?).to be true
      end
    end

    context 'when the instance is enrolled without add-on intent' do
      before do
        stub_application_setting(
          secrets_manager_instance_enrolled: true,
          secrets_manager_instance_add_on_requested_at: nil
        )
      end

      it 'returns false' do
        expect(described_class.add_on_requested?).to be false
      end
    end

    context 'when the add-on intent is stamped but the instance is not enrolled' do
      before do
        stub_application_setting(
          secrets_manager_instance_enrolled: false,
          secrets_manager_instance_add_on_requested_at: 1.day.ago
        )
      end

      it 'returns false' do
        expect(described_class.add_on_requested?).to be false
      end
    end
  end

  describe '.stamp_add_on_intent!' do
    def requested_at
      Gitlab::CurrentSettings.secrets_manager_instance_add_on_requested_at
    end

    # Specs run with in-memory settings that are only persisted on first write;
    # production always has the row, so persist it here.
    before do
      Gitlab::CurrentSettings.current_application_settings.save!
    end

    it 'stamps once and reports later calls as not the first', :aggregate_failures do
      expect(described_class.stamp_add_on_intent!).to be true

      first_stamp = requested_at
      expect(first_stamp).to be_present

      expect(described_class.stamp_add_on_intent!).to be false
      expect(requested_at).to eq(first_stamp)
    end
  end

  describe '.enrollment_allowed?' do
    before do
      allow(::License).to receive(:feature_available?).and_call_original
      allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
    end

    context 'when not on GitLab.com' do
      context 'when feature flag is enabled' do
        before do
          stub_feature_flags(secrets_manager_instance_enrollment: true)
        end

        it 'returns true' do
          expect(described_class.enrollment_allowed?).to be true
        end

        context 'when license is not available' do
          before do
            allow(::License).to receive(:feature_available?)
              .with(:native_secrets_management).and_return(false)
          end

          it 'returns false' do
            expect(described_class.enrollment_allowed?).to be false
          end
        end
      end

      context 'when feature flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_instance_enrollment: false)
        end

        it 'returns false' do
          expect(described_class.enrollment_allowed?).to be false
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns false' do
        expect(described_class.enrollment_allowed?).to be false
      end
    end
  end

  describe '.offline_license?' do
    let(:online_license) { instance_double(License, online_cloud_license?: true) }
    let(:offline_license) { instance_double(License, online_cloud_license?: false) }

    where(:license, :expected) do
      [
        [ref(:online_license), false],
        [ref(:offline_license), true],
        [nil, true]
      ]
    end

    with_them do
      before do
        allow(::License).to receive(:current).and_return(license)
      end

      it 'is true unless the license can reach CustomersDot' do
        expect(described_class.offline_license?).to be(expected)
      end
    end
  end

  describe '.paid_experience_allowed?' do
    before do
      allow(::License).to receive(:feature_available?).and_call_original
      allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
    end

    context 'when not on GitLab.com' do
      it 'returns true' do
        expect(described_class.paid_experience_allowed?).to be true
      end

      context 'when license is not available' do
        before do
          allow(::License).to receive(:feature_available?)
            .with(:native_secrets_management).and_return(false)
        end

        it 'returns false' do
          expect(described_class.paid_experience_allowed?).to be false
        end
      end

      context 'when the paid-experience feature flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: false)
        end

        it 'returns false' do
          expect(described_class.paid_experience_allowed?).to be false
        end
      end
    end

    context 'when on GitLab.com', :saas do
      it 'returns false' do
        expect(described_class.paid_experience_allowed?).to be false
      end
    end
  end
end
