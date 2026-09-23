# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::SsoController, feature_category: :system_access do
  let_it_be(:group) { create(:group) }
  let_it_be(:saml_provider) { create(:saml_provider, group: group) }

  before do
    stub_licensed_features(group_saml: true)
    allow(Devise).to receive(:omniauth_providers).and_return(['group_saml'])
  end

  it_behaves_like 'Base action controller' do
    subject(:request) { get sso_group_saml_providers_path(group, token: group.saml_discovery_token) }
  end

  describe 'GET #saml' do
    let(:private_group) { create(:group, :private) }

    before do
      create(:saml_provider, group: private_group)
      # Config.enabled? compares symbols, so a string here silently disables Group SAML.
      allow(Devise).to receive(:omniauth_providers).and_return([:group_saml])
    end

    context 'when signed out' do
      it 'renders the page when the discovery token matches' do
        get sso_group_saml_providers_path(private_group, token: private_group.saml_discovery_token)

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'redirects to sign in when the discovery token does not match' do
        get sso_group_saml_providers_path(private_group, token: 'not-the-discovery-token')

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
