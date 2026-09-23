# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidebars::UserSettings::Menus::GitlabCreditsDashboardMenu, :saas, feature_category: :consumables_cost_management do
  it_behaves_like 'User settings menu',
    link: '/-/profile/gitlab_credits_dashboard',
    title: s_('UsageBilling|GitLab Credits'),
    icon: 'gitlab-credits',
    active_routes: { controller: :gitlab_credits_dashboard }

  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- render? checks group membership and entitlement, which requires persisted records
  describe '#render?' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group_with_plan, plan: :premium_plan) }
    let(:context) { Sidebars::Context.new(current_user: user, container: nil) }

    subject(:menu) { described_class.new(context) }

    before_all do
      group.add_guest(user)
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    it 'renders for a human user who is a member of an entitled group' do
      expect(menu.render?).to be true
    end

    context 'when the user has no groups entitled to gitlab credits' do
      let_it_be(:user) { create(:user) }
      let_it_be(:group) { create(:group) }

      it 'does not render' do
        expect(menu.render?).to be false
      end
    end

    context 'when the user is not logged in' do
      let(:context) { Sidebars::Context.new(current_user: nil, container: nil) }

      it 'does not render' do
        expect(menu.render?).to be false
      end
    end

    context 'when the user is not a human' do
      let_it_be(:user) { create(:user, :service_account) }

      it 'does not render' do
        expect(menu.render?).to be false
      end
    end

    context 'when not on .com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'does not render' do
        expect(menu.render?).to be false
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(user_gitlab_credits_dashboard: false)
      end

      it 'does not render' do
        expect(menu.render?).to be false
      end
    end
  end
  # rubocop:enable RSpec/FactoryBot/AvoidCreate
end
