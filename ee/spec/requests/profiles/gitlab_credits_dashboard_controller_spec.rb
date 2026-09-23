# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Profiles::GitlabCreditsDashboardController, :saas, feature_category: :consumables_cost_management do
  let_it_be(:user) { create(:user, :with_namespace) }
  let_it_be_with_reload(:group) { create(:group_with_plan, plan: :premium_plan) }

  before do
    stub_ee_application_setting(should_check_namespace_plan: true)
    sign_in(user)
  end

  describe 'GET /-/profile/gitlab_credits_dashboard' do
    subject(:request) { get profile_gitlab_credits_dashboard_index_path }

    context 'when the user is a member of an entitled root group' do
      before_all do
        group.add_guest(user)
      end

      it 'returns 200 and exposes the group to the frontend', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('js-user-gitlab-credits-dashboard')
        expect(response.body).to include(group.name)
        expect(response.body).to include(group.full_path)
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(user_gitlab_credits_dashboard: false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when not on .com' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when the user has membership through a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      before_all do
        subgroup.add_guest(user)
      end

      it 'returns 200 and exposes the root group to the frontend', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(group.full_path)
      end
    end

    context 'when the user is a member of multiple entitled root groups' do
      let_it_be_with_reload(:other_group) { create(:group_with_plan, plan: :premium_plan) }

      before_all do
        group.add_guest(user)
        other_group.add_guest(user)
      end

      it 'exposes all groups to the frontend', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(group.full_path)
        expect(response.body).to include(other_group.full_path)
      end
    end

    context 'when the group is entitled via a gitlab_credits add-on' do
      let_it_be_with_reload(:group) { create(:group) }

      before_all do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :active, namespace: group)
        group.add_guest(user)
      end

      it 'returns 200' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the user has no group memberships' do
      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user is only a member of groups not entitled to gitlab credits' do
      let_it_be_with_reload(:group) { create(:group) }

      before_all do
        group.add_guest(user)
      end

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
