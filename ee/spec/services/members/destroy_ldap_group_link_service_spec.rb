# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::DestroyLdapGroupLinkService, feature_category: :system_access do
  let_it_be(:current_user) { create(:user) }

  before do
    stub_application_setting(allow_group_owners_to_manage_ldap: true)
    group.add_owner(current_user)
  end

  describe '.execute' do
    context 'with a plain link' do
      let_it_be(:group) { create(:group) }
      let_it_be(:ldap_group_link) { create(:ldap_group_link, group: group, provider: 'ldapmain') }

      subject(:execute) { described_class.execute(ldap_group_link, current_user: current_user) }

      it 'destroys the ldap group link' do
        expect { execute }.to change { group.ldap_group_links.count }.by(-1)
      end

      it 'locks the group row for the duration of the destroy and orphan check' do
        expect(group).to receive(:with_lock).and_call_original

        execute
      end

      it 'creates an audit event' do
        audit_context = {
          name: 'ldap_group_link_removed',
          author: current_user,
          scope: group,
          target: group,
          message: 'LDAP group link removed. CN - group1, Access Level - Guest, Provider - ldapmain',
          additional_details: {
            cn: 'group1',
            filter: nil,
            group_access: 'Guest',
            provider: 'ldapmain'
          }
        }

        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(audit_context).once.and_call_original

        execute
      end

      it 'does not create an audit event when the destroy is halted' do
        allow(ldap_group_link).to receive(:destroy).and_return(false)

        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        execute
      end
    end

    context 'when it was the last link for that provider' do
      let_it_be(:group) { create(:group) }
      let_it_be(:ldap_group_link) { create(:ldap_group_link, group: group, provider: 'ldapmain') }
      let_it_be(:member_user) { create(:user) }
      let_it_be_with_reload(:orphaned_member) do
        create(:group_member, :developer, group: group, user: member_user, ldap: true)
      end

      let_it_be(:identity) { create(:identity, user: member_user, provider: 'ldapmain') }

      subject(:execute) { described_class.execute(ldap_group_link, current_user: current_user) }

      it 'resets the ldap flag for members orphaned by the removal' do
        expect { execute }.to change { orphaned_member.reload.ldap? }.from(true).to(false)
      end
    end

    context 'when it was the last link for that provider, checking lock scope' do
      let_it_be(:group) { create(:group) }
      let_it_be(:ldap_group_link) { create(:ldap_group_link, group: group, provider: 'ldapmain') }

      subject(:execute) { described_class.execute(ldap_group_link, current_user: current_user) }

      it 'resets the ldap flag after the group lock is released, not inside it' do
        locked = false

        allow(group).to receive(:with_lock).and_wrap_original do |method, *args, &block|
          locked = true
          result = method.call(*args, &block)
          locked = false
          result
        end

        expect(Members::ResetOrphanedLdapProviderFlagsService).to receive(:execute) do
          expect(locked).to be(false)
        end

        execute
      end
    end

    context 'when other links remain for that provider' do
      let_it_be(:group) { create(:group) }
      let_it_be(:ldap_group_link) { create(:ldap_group_link, group: group, provider: 'ldapmain') }
      let_it_be(:other_ldap_group_link) do
        create(:ldap_group_link, group: group, cn: 'other-group', provider: 'ldapmain')
      end

      let_it_be(:member_user) { create(:user) }
      let_it_be_with_reload(:remaining_member) do
        create(:group_member, :developer, group: group, user: member_user, ldap: true)
      end

      let_it_be(:identity) { create(:identity, user: member_user, provider: 'ldapmain') }

      subject(:execute) { described_class.execute(ldap_group_link, current_user: current_user) }

      it 'does not reset the ldap flag' do
        expect { execute }.not_to change { remaining_member.reload.ldap? }
      end
    end

    context 'when the link has no provider column value set' do
      let_it_be(:group) { create(:group) }
      let_it_be(:null_provider_link) { create(:ldap_group_link, group: group, provider: nil) }
      let_it_be(:member_user) { create(:user) }
      let_it_be_with_reload(:orphaned_member) do
        create(:group_member, :developer, group: group, user: member_user, ldap: true)
      end

      let_it_be(:identity) { create(:identity, user: member_user, provider: 'ldapmain') }

      subject(:execute) { described_class.execute(null_provider_link, current_user: current_user) }

      it 'resets the ldap flag using the fallback provider' do
        expect { execute }.to change { orphaned_member.reload.ldap? }.from(true).to(false)
      end
    end

    context 'when the provider is no longer configured' do
      let_it_be(:group) { create(:group) }
      let_it_be(:member_user) { create(:user) }
      let_it_be_with_reload(:member) { create(:group_member, :developer, group: group, user: member_user, ldap: true) }
      let_it_be(:identity) { create(:identity, user: member_user, provider: 'ldap-decommissioned') }

      let(:decommissioned_link) do
        create(:ldap_group_link, group: group, cn: 'decommissioned-group', provider: 'ldap-decommissioned')
      end

      before do
        decommissioned_link
      end

      subject(:execute) { described_class.execute(decommissioned_link, current_user: current_user) }

      it 'does not reset the ldap flag' do
        expect { execute }.not_to change { member.reload.ldap? }
      end

      it 'still destroys the link' do
        expect { execute }.to change { group.ldap_group_links.count }.by(-1)
      end
    end

    context 'when the current user is not authorized' do
      let_it_be(:group) { create(:group) }
      let_it_be(:ldap_group_link) { create(:ldap_group_link, group: group, provider: 'ldapmain') }

      subject(:execute) { described_class.execute(ldap_group_link, current_user: current_user) }

      before do
        group.members.delete_all
      end

      it 'does not destroy the ldap group link' do
        expect { execute }.not_to change { group.ldap_group_links.count }
      end

      it 'does not create an audit event' do
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        execute
      end
    end
  end
end
