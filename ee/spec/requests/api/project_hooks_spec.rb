# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::ProjectHooks, :aggregate_failures, feature_category: :webhooks do
  describe 'duo_flow_callback_enabled' do
    let_it_be(:hook_group) { create(:group) }
    let_it_be(:hook_project) { create(:project, group: hook_group) }
    let_it_be(:owner) { create(:user, owner_of: hook_project) }
    let_it_be_with_reload(:duo_hook) { create(:project_hook, project: hook_project) }

    before do
      stub_feature_flags(duo_flow_callback_hooks: hook_project.root_ancestor)
    end

    it 'can be set when creating a project hook' do
      post api("/projects/#{hook_project.id}/hooks", owner), params: {
        url: 'https://example.com/callback',
        duo_flow_callback_enabled: true
      }

      expect(response).to have_gitlab_http_status(:created)
      expect(json_response['duo_flow_callback_enabled']).to be(true)
    end

    it 'can be updated on an existing project hook' do
      put api("/projects/#{hook_project.id}/hooks/#{duo_hook.id}", owner), params: {
        duo_flow_callback_enabled: true
      }

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['duo_flow_callback_enabled']).to be(true)
    end

    context 'when Duo Agent Platform is unavailable' do
      before do
        allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)
      end

      it 'rejects the attribute on create rather than dropping it' do
        post api("/projects/#{hook_project.id}/hooks", owner), params: {
          url: 'https://example.com/callback',
          duo_flow_callback_enabled: true
        }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'rejects the attribute on update rather than dropping it' do
        put api("/projects/#{hook_project.id}/hooks/#{duo_hook.id}", owner), params: {
          duo_flow_callback_enabled: true
        }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      # A client that GETs a hook and PUTs the payload back must not be rejected over a
      # value it never changed.
      it 'still accepts a request that disables the attribute' do
        put api("/projects/#{hook_project.id}/hooks/#{duo_hook.id}", owner), params: {
          duo_flow_callback_enabled: false
        }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['duo_flow_callback_enabled']).to be(false)
      end

      it 'still accepts a request that re-asserts a stored true' do
        duo_hook.update!(duo_flow_callback_enabled: true)

        put api("/projects/#{hook_project.id}/hooks/#{duo_hook.id}", owner), params: {
          url: duo_hook.url,
          duo_flow_callback_enabled: true
        }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['duo_flow_callback_enabled']).to be(true)
      end
    end
  end

  describe 'with admin_web_hook custom role' do
    before do
      stub_licensed_features(custom_roles: true)
      sign_in(user)
    end

    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:role) { create(:member_role, :guest, :admin_web_hook, namespace: group) }
    let_it_be(:membership) { create(:project_member, :guest, member_role: role, user: user, project: project) }
    let_it_be(:project_hook) { create(:project_hook, project: project, url: 'http://example.test/') }

    let(:hook) { create(:project_hook, project: project) }

    let(:list_url) { "/projects/#{project.id}/hooks" }
    let(:get_url) { "/projects/#{project.id}/hooks/#{project_hook.id}" }
    let(:add_url) { "/projects/#{project.id}/hooks" }
    let(:edit_url) { "/projects/#{project.id}/hooks/#{project_hook.id}" }
    let(:delete_url) { "/projects/#{project.id}/hooks/#{hook.id}" }

    it_behaves_like 'web-hook API endpoints with admin_web_hook custom role'
  end
end
