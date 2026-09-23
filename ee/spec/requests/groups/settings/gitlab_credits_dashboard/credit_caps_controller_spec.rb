# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Settings::GitlabCreditsDashboard::CreditCapsController,
  feature_category: :consumables_cost_management do
  include SaasRegistrationHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  before do
    sign_in(user)
  end

  describe 'GET /groups/*group_id/-/settings/gitlab_credits_dashboard/credit_caps' do
    subject(:request) { get group_settings_gitlab_credits_dashboard_credit_caps_path(group) }

    context 'when user is not signed in' do
      before do
        sign_out(user)
      end

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when in Self-Managed' do
      before_all do
        group.add_owner(user)
      end

      it 'renders 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when in .com', :saas_gitlab_com_subscriptions do
      before do
        stub_ee_application_setting(should_check_namespace_plan: true)
        stub_subscription_plans
        allow_next_instance_of(::Ai::UsageQuotaService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success)
        end
      end

      context 'when user is an owner' do
        before_all do
          group.add_owner(user)
        end

        it 'renders 404 for free group' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end

        context 'when group only has a gitlab_credits add-on' do
          before do
            create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :active, namespace: group)
          end

          it 'returns 200' do
            request

            expect(response).to have_gitlab_http_status(:ok)
          end
        end

        context 'when group has plan with gitlab credits entitlement' do
          subject(:request) { get group_settings_gitlab_credits_dashboard_credit_caps_path(paid_group) }

          let_it_be_with_reload(:paid_group) { create(:group_with_plan, plan: :premium_plan) }

          before_all do
            paid_group.add_owner(user)
          end

          it 'returns 200' do
            request

            expect(response).to have_gitlab_http_status(:ok)
          end

          it 'renders 404 when feature flag is disabled' do
            stub_feature_flags(credit_caps_ui: false)
            request

            expect(response).to have_gitlab_http_status(:not_found)
          end

          it 'pushes credit_caps_ui feature flag to the frontend' do
            request

            expect(response.body).to have_pushed_frontend_feature_flags(creditCapsUi: true)
          end
        end
      end

      context 'when user is not an owner' do
        subject(:request) { get group_settings_gitlab_credits_dashboard_credit_caps_path(paid_group) }

        let_it_be_with_reload(:paid_group) { create(:group_with_plan, plan: :premium_plan) }

        before_all do
          paid_group.add_maintainer(user)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
