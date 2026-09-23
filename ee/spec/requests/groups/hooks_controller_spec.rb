# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::HooksController, feature_category: :webhooks do
  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user, owner_of: group) }
  let_it_be_with_reload(:hook) { create(:group_hook, group: group) }

  before do
    stub_licensed_features(group_webhooks: true)
    sign_in(user)
  end

  describe 'duo_flow_callback_enabled' do
    before do
      stub_feature_flags(duo_flow_callback_hooks: group.root_ancestor)
    end

    # The attribute has to be listed in hook_param_names, otherwise the form submits it
    # and Rails discards it as unpermitted, leaving the checkbox with no effect.
    it 'persists the attribute on create' do
      post group_hooks_path(group), params: {
        hook: { url: 'http://example.com', duo_flow_callback_enabled: true }
      }

      expect(group.hooks.order_id_desc.take.duo_flow_callback_enabled).to be(true)
    end

    it 'persists the attribute on update' do
      put group_hook_path(group, hook), params: {
        hook: { url: hook.url, duo_flow_callback_enabled: true }
      }

      expect(hook.reload.duo_flow_callback_enabled).to be(true)
    end

    # The form omits the checkbox when the feature is unavailable, so these requests stand
    # in for a hand-rolled one.
    context 'when the feature flag is disabled for the root namespace' do
      before do
        stub_feature_flags(duo_flow_callback_hooks: false)
      end

      it 'does not set the attribute on create' do
        post group_hooks_path(group), params: {
          hook: { url: 'http://example.com', duo_flow_callback_enabled: true }
        }

        expect(group.hooks.order_id_desc.take.duo_flow_callback_enabled).to be(false)
      end

      it 'does not set the attribute on update' do
        put group_hook_path(group, hook), params: {
          hook: { url: hook.url, duo_flow_callback_enabled: true }
        }

        expect(hook.reload.duo_flow_callback_enabled).to be(false)
      end
    end

    context 'when Duo Agent Platform is unavailable' do
      before do
        allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)
      end

      it 'does not set the attribute on create' do
        post group_hooks_path(group), params: {
          hook: { url: 'http://example.com', duo_flow_callback_enabled: true }
        }

        expect(group.hooks.order_id_desc.take.duo_flow_callback_enabled).to be(false)
      end

      it 'does not set the attribute on update' do
        put group_hook_path(group, hook), params: {
          hook: { url: hook.url, duo_flow_callback_enabled: true }
        }

        expect(hook.reload.duo_flow_callback_enabled).to be(false)
      end

      it 'does not render the settings section' do
        get group_hooks_path(group)

        expect(response.body).not_to include(s_('Webhooks|Send Duo flow events to this webhook'))
      end
    end

    # #index builds an unsaved hook, so hook.parent is nil there. The flag actor comes
    # from the controller instead, otherwise the section renders for every namespace.
    describe 'the settings section on the new-hook form' do
      let(:checkbox_label) { s_('Webhooks|Send Duo flow events to this webhook') }

      it 'renders when the flag is enabled for the root ancestor' do
        get group_hooks_path(group)

        expect(response.body).to include(checkbox_label)
      end

      it 'does not render when the flag is disabled' do
        stub_feature_flags(duo_flow_callback_hooks: false)

        get group_hooks_path(group)

        expect(response.body).not_to include(checkbox_label)
      end

      it 'does not render when the flag is enabled for a different namespace' do
        stub_feature_flags(duo_flow_callback_hooks: create(:group))

        get group_hooks_path(group)

        expect(response.body).not_to include(checkbox_label)
      end
    end
  end
end
