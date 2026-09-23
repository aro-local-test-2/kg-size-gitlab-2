# frozen_string_literal: true

require 'spec_helper'

# The gating rules are covered end to end through
# Resolvers::Ai::FoundationalChatAgentsResolver. These examples cover the finder's own
# contract, so a second caller can rely on it without going through that resolver.
RSpec.describe Ai::FoundationalChatAgentsFinder, feature_category: :workflow_catalog do
  include GraphqlHelpers

  let_it_be_with_reload(:current_user) { create(:user) }
  let_it_be(:root_namespace) { create(:group) }
  let_it_be(:namespace_ai_settings) do
    create(:namespace_ai_settings, foundational_agents_default_enabled: true, namespace: root_namespace)
  end

  let_it_be(:project) { create(:project, namespace: root_namespace) }
  let_it_be(:default_organization) { create(:organization) }
  let_it_be_with_reload(:setting) { create(:ai_settings, foundational_agents_default_enabled: true) }

  let(:user) { current_user }
  let(:project_id) { nil }
  let(:namespace_id) { nil }

  subject(:references) do
    described_class.new(user, project_id: project_id, namespace_id: namespace_id).execute.map(&:reference)
  end

  before_all do
    root_namespace.add_developer(current_user)
  end

  before do
    allow(::Organizations::Organization).to receive(:default_organization).and_return(default_organization)
    allow(::Ai::Setting).to receive(:instance).and_return(setting)
  end

  context 'when running on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    context 'with a project' do
      let(:project_id) { global_id_of(project) }

      it 'returns the agents enabled for the namespace of the project' do
        expect(references).to include('chat', 'duo_planner', 'ci_expert_agent')
      end

      it 'orders the agents by id' do
        ids = described_class.new(user, project_id: project_id).execute.map(&:id)

        expect(ids).to eq(ids.sort)
      end

      context 'when the namespace is not licensed for AI features' do
        it 'excludes the ultimate only agents' do
          expect(references).not_to include('security_analyst_agent')
        end
      end

      context 'when the namespace is licensed for AI features' do
        before do
          stub_licensed_features(ai_features: true)
        end

        it 'includes the ultimate only agents' do
          expect(references).to include('security_analyst_agent')
        end
      end
    end

    context 'with a namespace' do
      let(:namespace_id) { global_id_of(root_namespace) }

      it 'resolves the namespace the same way it resolves a project' do
        expect(references).to eq(described_class.new(user, project_id: global_id_of(project)).execute.map(&:reference))
      end
    end

    context 'without a user' do
      let(:user) { nil }
      let(:project_id) { global_id_of(project) }

      it 'returns only the duo chat agents' do
        expect(references).to eq(::Ai::FoundationalChatAgent.only_duo_chat_agent.map(&:reference))
      end
    end

    describe 'the Orbit agent' do
      let(:project_id) { global_id_of(project) }

      it 'is excluded when the user has Orbit turned off' do
        allow(::Ai::Orbit::Settings).to receive(:agent_enabled?).with(current_user).and_return(false)

        expect(references).not_to include('orbit_agent')
      end

      it 'is included when the user has Orbit turned on' do
        allow(::Ai::Orbit::Settings).to receive(:agent_enabled?).with(current_user).and_return(true)

        expect(references).to include('orbit_agent')
      end
    end
  end

  context 'when running on a self-managed instance' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it 'reads the agents from the default organization rather than a namespace' do
      expect(default_organization).to receive(:enabled_foundational_agents).and_call_original

      references
    end
  end
end
