# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Oauth::AuthorizationsController, :with_current_organization, feature_category: :system_access do
  let_it_be(:user, freeze: false) { create(:user, organizations: [current_organization]) }
  let_it_be_with_reload(:application) do
    create(:oauth_application, :dynamic,
      name: '[Unverified Dynamic Application] kiro',
      scopes: 'mcp',
      redirect_uri: 'http://example.com')
  end

  let(:params) do
    {
      client_id: application.uid,
      response_type: 'code',
      scope: 'mcp',
      redirect_uri: application.redirect_uri,
      state: SecureRandom.hex,
      code_challenge: 'code_challenge_value_abcdefghijklmnop',
      code_challenge_method: 'S256'
    }
  end

  before do
    sign_in(user)
  end

  describe 'POST #create stamping the authorizing user onto a dynamic application' do
    context 'on GitLab.com', :saas_skip_dynamic_oauth_app_user_stamp do
      it 'does not stamp the authorizing user onto the name' do
        expect { post oauth_authorization_path, params: params }
          .not_to change { application.reload.name }.from('[Unverified Dynamic Application] kiro')
      end
    end

    context 'on a self-managed instance' do
      it 'stamps the authorizing user onto the name' do
        post oauth_authorization_path, params: params

        expect(application.reload.name)
          .to eq("[Unverified Dynamic Application] kiro — authorized by @#{user.username}")
      end
    end
  end
end
