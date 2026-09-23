# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::HooksController, feature_category: :webhooks do
  let_it_be(:admin) { create(:admin) }

  before do
    sign_in(admin)
  end

  # System hooks render the shared webhook form but belong to no project or group, so the
  # Duo Agent Platform section has to sit out rather than dereference a nil container.
  describe 'GET #index', :enable_admin_mode do
    it 'renders the form without the Duo Agent Platform section' do
      get admin_hooks_path

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).not_to include(s_('Webhooks|Send Duo flow events to this webhook'))
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(duo_flow_callback_hooks: false)
      end

      it 'renders the form without the Duo Agent Platform section' do
        get admin_hooks_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).not_to include(s_('Webhooks|Send Duo flow events to this webhook'))
      end
    end

    context 'when Duo Agent Platform is available for the instance' do
      before do
        allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(true)
      end

      it 'renders the form without the Duo Agent Platform section' do
        get admin_hooks_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).not_to include(s_('Webhooks|Send Duo flow events to this webhook'))
      end
    end
  end
end
