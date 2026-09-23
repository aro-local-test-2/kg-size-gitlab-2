# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::OrganizationUsers::UpdateService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_owner, freeze: false) { create(:organization_owner, organization:) }

  describe '#execute' do
    let_it_be_with_reload(:organization_user) { create(:organization_user, organization:) }
    let(:access_level) { Gitlab::Access::OWNER }
    let(:params) { { access_level: access_level } }

    subject(:execute) do
      described_class.new(organization_user, current_user: organization_owner.user, params: params).execute
    end

    before do
      allow(Authn::IamDataAccessService).to receive(:configured?).and_return(true)
    end

    context 'when access_level changes from default to owner' do
      it 'enqueues GrantOwnerRoleWorker with the acting owner as the third argument' do
        expect(Authz::Organizations::GrantOwnerRoleWorker).to receive(:perform_async)
          .with(organization_user.organization_id, organization_user.user_id, organization_owner.user.id)
        expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when access_level changes from owner to default' do
      let_it_be_with_reload(:organization_user) { create(:organization_owner, organization:) }

      let(:access_level) { 'default' }

      it 'enqueues RevokeOwnerRoleWorker with the acting owner as the third argument' do
        expect(Authz::Organizations::RevokeOwnerRoleWorker).to receive(:perform_async)
          .with(organization_user.organization_id, organization_user.user_id, organization_owner.user.id)
        expect(Authz::Organizations::GrantOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when access_level is unchanged' do
      let(:access_level) { organization_user.access_level_before_type_cast }

      it 'does not enqueue a worker' do
        expect(Authz::Organizations::GrantOwnerRoleWorker).not_to receive(:perform_async)
        expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when the update fails' do
      it 'does not enqueue a worker' do
        allow(organization_user).to receive(:update).and_return(false)

        expect(Authz::Organizations::GrantOwnerRoleWorker).not_to receive(:perform_async)
        expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when the IAM data access service is not configured' do
      before do
        allow(Authn::IamDataAccessService).to receive(:configured?).and_return(false)
      end

      it 'does not enqueue GrantOwnerRoleWorker' do
        expect(Authz::Organizations::GrantOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end

      context 'when access_level changes from owner to default' do
        let_it_be_with_reload(:organization_user) { create(:organization_owner, organization:) }

        let(:access_level) { 'default' }

        it 'does not enqueue RevokeOwnerRoleWorker' do
          expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

          execute
        end
      end
    end
  end
end
