# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::WebHooks::DuoFlowCallback, feature_category: :webhooks do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  describe '.available?' do
    context 'when Duo Agent Platform is available' do
      it 'is available for a project' do
        expect(described_class.available?(project)).to be(true)
      end

      it 'is available for a group that has no project' do
        expect(described_class.available?(create(:group))).to be(true)
      end

      # A system hook has no container, and the Duo Agent Platform check answers true for
      # a nil one on Self-Managed, where it falls back to instance settings.
      it 'is unavailable without a container' do
        expect(described_class.available?(nil)).to be(false)
      end
    end

    context 'when Duo Agent Platform is unavailable' do
      before do
        allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)
      end

      it 'is unavailable for a project' do
        expect(described_class.available?(project)).to be(false)
      end

      it 'is unavailable for a group' do
        expect(described_class.available?(group)).to be(false)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(duo_flow_callback_hooks: false)
      end

      it 'is unavailable even though Duo Agent Platform is' do
        expect(described_class.available?(project)).to be(false)
      end
    end

    context 'on GitLab.com', :saas do
      let_it_be_with_reload(:saas_group) { create(:group) }
      let_it_be(:saas_project) { create(:project, group: saas_group) }

      before do
        saas_group.ai_settings.update!(duo_agent_platform_enabled: duo_agent_platform_enabled)
      end

      context 'when the root namespace has Duo Agent Platform enabled' do
        let(:duo_agent_platform_enabled) { true }

        it 'is available for a project' do
          expect(described_class.available?(saas_project)).to be(true)
        end

        it 'is available for the group itself' do
          expect(described_class.available?(saas_group)).to be(true)
        end
      end

      context 'when the root namespace has Duo Agent Platform disabled' do
        let(:duo_agent_platform_enabled) { false }

        it 'is unavailable for a project' do
          expect(described_class.available?(saas_project)).to be(false)
        end

        it 'is unavailable for the group itself' do
          expect(described_class.available?(saas_group)).to be(false)
        end
      end
    end
  end
end
