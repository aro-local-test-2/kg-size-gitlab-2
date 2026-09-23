# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::CreateLdapGroupLinkService, feature_category: :system_access do
  subject(:execute) { described_class.execute(group: group, params: params, current_user: current_user) }

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user) }

  before_all do
    group.add_owner(current_user)
  end

  before do
    stub_application_setting(allow_group_owners_to_manage_ldap: true)
  end

  context 'with a cn' do
    let(:params) { { cn: 'group1', group_access: Gitlab::Access::GUEST, provider: 'ldapmain' } }

    it 'creates the ldap group link' do
      expect { execute }.to change { group.ldap_group_links.count }.by(1)
    end

    it 'returns the persisted link' do
      expect(execute).to be_persisted
    end

    it 'creates an audit event' do
      audit_context = {
        name: 'ldap_group_link_created',
        author: current_user,
        scope: group,
        target: group,
        message: 'LDAP group link created. CN - group1, Access Level - Guest, Provider - ldapmain',
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
  end

  context 'with a filter' do
    let(:params) { { filter: '(cn=group1)', group_access: Gitlab::Access::GUEST, provider: 'ldapmain' } }

    it 'creates an audit event with the filter identifier' do
      audit_context = {
        name: 'ldap_group_link_created',
        author: current_user,
        scope: group,
        target: group,
        message: 'LDAP group link created. Filter - (cn=group1), Access Level - Guest, Provider - ldapmain',
        additional_details: {
          cn: nil,
          filter: '(cn=group1)',
          group_access: 'Guest',
          provider: 'ldapmain'
        }
      }

      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(audit_context).once.and_call_original

      execute
    end
  end

  context 'with invalid params' do
    let(:params) { { group_access: Gitlab::Access::GUEST, provider: 'ldapmain' } }

    it 'does not persist the link' do
      expect(execute).not_to be_persisted
    end

    it 'does not create an audit event' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      execute
    end

    it 'does not create the ldap group link' do
      expect { execute }.not_to change { group.ldap_group_links.count }
    end
  end

  context 'when the current user is not authorized' do
    let(:params) { { cn: 'group1', group_access: Gitlab::Access::GUEST, provider: 'ldapmain' } }

    before do
      group.members.delete_all
    end

    it 'does not create the ldap group link' do
      expect { execute }.not_to change { group.ldap_group_links.count }
    end

    it 'does not create an audit event' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

      execute
    end

    it 'returns an unpersisted link with an error' do
      link = execute

      expect(link).not_to be_persisted
      expect(link.errors[:base]).to include('Unauthorized')
    end
  end
end
