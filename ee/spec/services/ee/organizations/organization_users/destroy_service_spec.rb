# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::OrganizationUsers::DestroyService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_owner) { create(:organization_owner, organization: organization) }

  subject(:execute) do
    described_class.new(organization_user, current_user: current_user).execute
  end

  before do
    allow(Authn::IamDataAccessService).to receive(:configured?).and_return(true)
  end

  context 'when removing an owner' do
    let_it_be_with_reload(:organization_owner) { create(:organization_owner, organization: organization) }
    let(:organization_user) { organization_owner }
    let(:current_user) { other_owner.user }

    before_all do
      # A user must remain associated with at least one organization, so the
      # target needs a second membership for the destroy itself to succeed.
      create(:organization_user, user: organization_owner.user)
    end

    it 'enqueues RevokeOwnerRoleWorker with the acting user as the third argument' do
      expect(Authz::Organizations::RevokeOwnerRoleWorker).to receive(:perform_async)
        .with(organization.id, organization_owner.user_id, other_owner.user.id)

      execute
    end

    context 'when the owner removes themselves' do
      let(:current_user) { organization_owner.user }

      it 'enqueues RevokeOwnerRoleWorker with themselves as the acting user' do
        expect(Authz::Organizations::RevokeOwnerRoleWorker).to receive(:perform_async)
          .with(organization.id, organization_owner.user_id, organization_owner.user_id)

        execute
      end
    end

    context 'when the IAM data access service is not configured' do
      before do
        allow(Authn::IamDataAccessService).to receive(:configured?).and_return(false)
      end

      it 'does not enqueue RevokeOwnerRoleWorker' do
        expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when the removal fails' do
      let(:organization_user) { create(:organization_owner, organization: organization) }

      before do
        create(:organization_user, user: organization_user.user)
        allow(organization_user).to receive(:destroy).and_return(false)
      end

      it 'does not enqueue RevokeOwnerRoleWorker' do
        expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

        execute
      end
    end
  end

  context 'when removing a non-owner' do
    let(:organization_user) { create(:organization_user, organization: organization) }
    let(:current_user) { other_owner.user }

    it 'does not enqueue RevokeOwnerRoleWorker' do
      expect(Authz::Organizations::RevokeOwnerRoleWorker).not_to receive(:perform_async)

      execute
    end
  end
end
