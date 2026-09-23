# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'dashboard/todos/index', feature_category: :notifications do
  let(:user) { build_stubbed(:user) }
  let_it_be(:groups_requiring_reauth) { [create(:group)] } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the reauth partial calls Group#saml_discovery_token, which persists the record (save!)

  before do
    allow(view).to receive(:render_if_exists).and_call_original
    allow(view).to receive(:render_dashboard_ultimate_trial)
    allow(view).to receive_messages(current_user: user, user_groups_requiring_reauth: groups_requiring_reauth)
  end

  context 'when the user has todos' do
    before do
      allow(user).to receive(:todos).and_return([build_stubbed(:todo)])
    end

    it 'renders the SAML reauthentication notice partial with the groups requiring reauth' do
      render

      expect(view).to have_rendered(partial: 'shared/dashboard/saml_reauth_notice',
        locals: { groups_requiring_saml_reauth: groups_requiring_reauth })
    end
  end

  context 'when the user has no todos' do
    before do
      allow(user).to receive(:todos).and_return([])
    end

    it 'does not render the SAML reauthentication notice partial' do
      render

      expect(view).not_to have_rendered(partial: 'shared/dashboard/saml_reauth_notice')
    end
  end
end
