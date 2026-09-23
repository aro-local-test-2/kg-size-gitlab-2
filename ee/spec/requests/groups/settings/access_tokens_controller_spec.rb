# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Settings::AccessTokensController, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:resource) { create(:group, owners: user) }

  before do
    sign_in(user)
    stub_licensed_features(resource_access_token: true)
  end

  describe 'POST /:namespace/-/settings/access_tokens' do
    let(:access_token_params) { { name: 'Nerd bot', scopes: ["api"], expires_at: 1.month.from_now } }
    let(:ultimate_plan) { build(:ultimate_plan) }

    subject(:request) do
      post group_settings_access_tokens_path(resource), params: { resource_access_token: access_token_params }
    end

    context 'when has trial subscription', :saas do
      before do
        create(:gitlab_subscription, :active_trial, namespace: resource, hosted_plan: ultimate_plan)
      end

      it 'cannot create token' do
        expect { request }.not_to change { PersonalAccessToken.count }
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when has non-trial subscription', :saas do
      before do
        create(:gitlab_subscription, namespace: resource, hosted_plan: ultimate_plan)
      end

      it 'can create token' do
        expect { request }.to change { PersonalAccessToken.count }.from(0).to(1)
        expect(response).to have_gitlab_http_status(:success)
      end
    end
  end

  describe 'GET /:namespace/-/settings/access_tokens', :saas do
    let(:premium_plan) { Hashie::Mash.new(code: ::Plan::PREMIUM, id: 2, name: 'Premium') }

    subject(:request) { get group_settings_access_tokens_path(resource) }

    before do
      # Free tier: token creation is unavailable, so the upsell branch renders.
      stub_licensed_features(resource_access_token: false)
      allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
        allow(service).to receive(:execute).and_return([premium_plan])
      end
    end

    it 'renders the premium offer card and suppresses the legacy notice' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('Try group access tokens with Premium')
      expect(response.body).not_to include('Group access token creation is disabled in this group.')
    end

    context 'when GitLab.com subscriptions are unavailable' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'renders the legacy notice and not the card' do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('Group access token creation is disabled in this group.')
        expect(response.body).not_to include('Try group access tokens with Premium')
      end
    end
  end
end
