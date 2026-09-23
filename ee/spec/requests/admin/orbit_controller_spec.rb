# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::OrbitController, :enable_admin_mode, feature_category: :knowledge_graph do
  include AdminModeHelper
  include StubENV

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  before do
    stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
    ApplicationSetting.create_from_defaults unless ApplicationSetting.current_without_cache
    stub_licensed_features(orbit: true)
    allow(Feature).to receive(:enabled?).and_call_original
    allow(Feature).to receive(:enabled?).with(:knowledge_graph, admin).and_return(true)
    allow(Feature).to receive(:enabled?).with(:knowledge_graph, user).and_return(true)
    allow(Analytics::KnowledgeGraph).to receive(:enabled_for?).with(admin).and_return(true)
    allow(Analytics::KnowledgeGraph).to receive(:enabled_for?).with(user).and_return(true)
  end

  describe 'GET /admin/orbit' do
    it 'renders the Orbit settings form for an administrator' do
      sign_in(admin)
      enable_admin_mode!(admin)

      get admin_orbit_path

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('Index root namespaces automatically')
    end

    it 'returns not found when Orbit is unlicensed' do
      sign_in(admin)
      enable_admin_mode!(admin)
      stub_licensed_features(orbit: false)

      get admin_orbit_path

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns not found for a non-administrator' do
      sign_in(user)

      get admin_orbit_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'PATCH /admin/orbit' do
    before do
      sign_in(admin)
      enable_admin_mode!(admin)
    end

    it 'updates the auto-index setting' do
      patch admin_orbit_path, params: {
        application_setting: { orbit_auto_index_root_namespace: '1' }
      }

      expect(response).to redirect_to(admin_orbit_path)
      expect(ApplicationSetting.current.orbit_auto_index_root_namespace).to be(true)
      expect(flash[:notice]).to eq('Application settings saved successfully')
    end

    it 'does not permit settings outside the Orbit registry' do
      patch admin_orbit_path, params: {
        application_setting: {
          orbit_auto_index_root_namespace: '0',
          repository_size_limit: 999_999
        }
      }

      expect(response).to redirect_to(admin_orbit_path)
      expect(ApplicationSetting.current.repository_size_limit).to eq(0)
    end

    it 'returns not found without update access' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(admin, :update_knowledge_graph_setting, :global)
        .and_return(false)

      patch admin_orbit_path, params: {
        application_setting: { orbit_auto_index_root_namespace: '1' }
      }

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
