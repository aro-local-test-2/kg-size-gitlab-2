# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::GitlabCreditsDashboard::CreditCapsController,
  :enable_admin_mode, feature_category: :consumables_cost_management do
  let_it_be(:admin) { create(:admin) }

  before do
    sign_in(admin)
  end

  describe 'GET /admin/gitlab_credits_dashboard/credit_caps' do
    subject(:request) { get admin_gitlab_credits_dashboard_credit_caps_path }

    context 'when user is not signed in' do
      before do
        sign_out(admin)
      end

      it 'redirects to the login page' do
        request

        expect(response).to have_gitlab_http_status(:redirect)
        expect(response).to redirect_to(new_user_session_path)
      end
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

    it 'renders 404 when in .com', :saas do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'renders 404 when unlicensed' do
      allow(License).to receive(:current).and_return(nil)
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end

    context 'when instance only has a gitlab_credits add-on' do
      before do
        stub_licensed_features(usage_billing: false)
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :active, :self_managed)
        stub_request(:head, %r{https://customers\.staging\.gitlab\.com/api/v1/consumers/resolve})
          .to_return(status: 200, body: "", headers: {})
      end

      it 'returns 200' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    it 'pushes credit_caps_ui feature flag to the frontend' do
      request

      expect(response.body).to have_pushed_frontend_feature_flags(creditCapsUi: true)
    end
  end
end
