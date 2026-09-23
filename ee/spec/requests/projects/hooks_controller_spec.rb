# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::HooksController, feature_category: :webhooks do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }
  let_it_be_with_reload(:hook) { create(:project_hook, project: project) }

  before do
    sign_in(user)
  end

  describe 'duo_flow_callback_enabled' do
    before do
      stub_feature_flags(duo_flow_callback_hooks: project.root_ancestor)
    end

    it 'persists the attribute on create' do
      post project_hooks_path(project), params: {
        hook: { url: 'http://example.com', duo_flow_callback_enabled: true }
      }

      expect(project.hooks.order_id_desc.take.duo_flow_callback_enabled).to be(true)
    end

    it 'persists the attribute on update' do
      put project_hook_path(project, hook), params: {
        hook: { url: hook.url, duo_flow_callback_enabled: true }
      }

      expect(hook.reload.duo_flow_callback_enabled).to be(true)
    end

    context 'when Duo Agent Platform is unavailable' do
      before do
        allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)
      end

      it 'does not set the attribute on create' do
        post project_hooks_path(project), params: {
          hook: { url: 'http://example.com', duo_flow_callback_enabled: true }
        }

        expect(project.hooks.order_id_desc.take.duo_flow_callback_enabled).to be(false)
      end

      it 'does not set the attribute on update' do
        put project_hook_path(project, hook), params: {
          hook: { url: hook.url, duo_flow_callback_enabled: true }
        }

        expect(hook.reload.duo_flow_callback_enabled).to be(false)
      end
    end
  end

  # #index builds an unsaved hook, so hook.parent is nil there. The flag actor comes from
  # the controller instead, otherwise the section renders for every namespace.
  describe 'the Duo Agent Platform section on the new-hook form' do
    let(:checkbox_label) { s_('Webhooks|Send Duo flow events to this webhook') }

    it 'renders when the flag is enabled for the root ancestor' do
      stub_feature_flags(duo_flow_callback_hooks: project.root_ancestor)

      get project_hooks_path(project)

      expect(response.body).to include(checkbox_label)
    end

    it 'does not render when the flag is disabled' do
      stub_feature_flags(duo_flow_callback_hooks: false)

      get project_hooks_path(project)

      expect(response.body).not_to include(checkbox_label)
    end

    it 'does not render when the flag is enabled for a different namespace' do
      stub_feature_flags(duo_flow_callback_hooks: create(:group))

      get project_hooks_path(project)

      expect(response.body).not_to include(checkbox_label)
    end

    it 'does not render when Duo Agent Platform is unavailable' do
      stub_feature_flags(duo_flow_callback_hooks: project.root_ancestor)
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)

      get project_hooks_path(project)

      expect(response.body).not_to include(checkbox_label)
    end
  end
end
