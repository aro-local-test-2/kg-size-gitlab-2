# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/group_members/_ldap_sync', feature_category: :system_access do
  let(:user) { build_stubbed(:user) }
  let(:group) { build_stubbed(:group) }
  let(:ldap_group_link) { build_stubbed(:ldap_group_link, group: group, cn: 'group1') }

  before do
    stub_config(ldap: { enabled: true })
    allow(group).to receive_messages(ldap_synced?: true, ldap_group_links: [ldap_group_link])
    allow(view).to receive(:current_user).and_return(user)
    assign(:group, group)
  end

  it 'renders the LDAP sync banner' do
    render

    expect(rendered).to have_content('managed with LDAP')
  end

  context 'when restricted access is enabled' do
    before do
      stub_ee_application_setting(seat_control: ::ApplicationSetting::SEAT_CONTROL_BLOCK_OVERAGES)
    end

    it 'shows the restricted access warning' do
      render

      expect(rendered).to have_content(
        'new users provisioned through LDAP sync are assigned the non-billable Minimal Access role'
      )
    end
  end

  context 'when restricted access is not enabled' do
    it 'does not show the restricted access warning' do
      render

      expect(rendered).not_to have_content(
        'new users provisioned through LDAP sync are assigned the non-billable Minimal Access role'
      )
    end
  end

  context 'when bso_minimal_access_fallback feature flag is disabled' do
    before do
      stub_ee_application_setting(seat_control: ::ApplicationSetting::SEAT_CONTROL_BLOCK_OVERAGES)
      stub_feature_flags(bso_minimal_access_fallback: false)
    end

    it 'does not show the restricted access warning' do
      render

      expect(rendered).not_to have_content(
        'new users provisioned through LDAP sync are assigned the non-billable Minimal Access role'
      )
    end
  end

  context 'when the last LDAP sync failed' do
    before do
      allow(group).to receive_messages(
        ldap_sync_failed?: true,
        ldap_sync_error: 'Members and requesters is invalid'
      )
    end

    context 'when the user can admin the group' do
      before do
        allow(view).to receive(:can?).with(user, :admin_group, group).and_return(true)
      end

      it 'shows the most recent sync error', :aggregate_failures do
        render

        expect(rendered).to have_content('The most recent LDAP sync failed')
        expect(rendered).to have_content('Members and requesters is invalid')
      end
    end

    context 'when the user cannot admin the group' do
      before do
        allow(view).to receive(:can?).and_return(false)
      end

      it 'does not show the most recent sync error' do
        render

        expect(rendered).not_to have_content('The most recent LDAP sync failed')
      end
    end
  end
end
