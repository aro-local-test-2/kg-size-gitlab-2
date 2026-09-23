# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::UpdateService, feature_category: :security_policy_management do
  include_context 'with the policy store experiment active'

  let_it_be_with_reload(:organization) { create(:organization) }
  let_it_be(:owner) { create(:user, owner_of: organization) }
  let_it_be(:non_member) { create(:user) }

  describe '#execute' do
    # The availability check must not run ahead of the permission check, or an
    # unauthorized caller could probe whether the experiment is available.
    context 'when the caller lacks permission and the experiment is unavailable' do
      before do
        stub_licensed_features(security_orchestration_policies: false)
      end

      it 'reports the permission failure, not the availability state' do
        result = described_class.new(
          organization,
          current_user: non_member,
          params: { policy_store_experiment_enabled: true }
        ).execute

        expect(result).to be_error
        expect(result.message).to contain_exactly('You have insufficient permissions to update the organization')
        expect(::Organizations::OrganizationSetting.for(organization.id).policy_store_experiment_enabled).to be_nil
      end
    end

    context 'when the caller does not pass policy_store_experiment_enabled' do
      it 'updates the organization without touching the settings record' do
        result = described_class.new(
          organization,
          current_user: owner,
          params: { name: 'Renamed org' }
        ).execute

        expect(result).to be_success
        expect(organization.reload.name).to eq('Renamed org')
        expect(::Organizations::OrganizationSetting.for(organization.id).policy_store_experiment_enabled).to be_nil
      end
    end

    context 'when opting in' do
      def execute_service(params)
        described_class.new(organization, current_user: owner, params: params).execute
      end

      context 'when the settings record does not exist yet' do
        it 'creates it with the opt-in set' do
          result = execute_service(policy_store_experiment_enabled: true)

          expect(result).to be_success
          expect(organization.settings.reload.policy_store_experiment_enabled).to be(true)
        end
      end

      context 'when the settings record already carries another key' do
        before do
          ::Organizations::OrganizationSetting.for(organization.id).update!(security_tracked_context_quota: 42)
        end

        it 'merges the opt-in without clobbering the existing key' do
          result = execute_service(policy_store_experiment_enabled: true)

          expect(result).to be_success
          settings = organization.settings.reload
          expect(settings.policy_store_experiment_enabled).to be(true)
          expect(settings.security_tracked_context_quota).to eq(42)
        end
      end
    end
  end
end
