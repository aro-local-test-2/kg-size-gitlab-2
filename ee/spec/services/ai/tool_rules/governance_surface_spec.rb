# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::GovernanceSurface, feature_category: :ai_agents do
  let_it_be(:container) { create(:group) }

  # The Duo Developer flow's real reference; a literal here guards the allowlist against drift.
  let(:duo_developer_flow) { 'developer/v1' }

  describe '.for' do
    context 'when the background-governance flag is enabled' do
      it 'returns :background for a background environment with an allowlisted flow' do
        %w[web ambient].each do |env|
          expect(
            described_class.for(environment: env, container: container, workflow_definition: duo_developer_flow)
          ).to eq(:background)
        end
      end

      it 'returns nil for a reference that is not a catalog flow, even with an allowlisted base name' do
        expect(
          described_class.for(environment: 'web', container: container, workflow_definition: 'developer/not-a-flow')
        ).to be_nil
      end

      it 'returns nil for a background environment when the flow is not allowlisted' do
        %w[web ambient].each do |env|
          expect(
            described_class.for(environment: env, container: container, workflow_definition: 'security_review/v1')
          ).to be_nil
        end
      end

      it 'returns nil for a background environment when no flow is given' do
        expect(described_class.for(environment: 'ambient', container: container)).to be_nil
      end

      it 'never returns :background for a non-background environment even with an allowlisted flow' do
        %w[ide chat chat_partial].each do |env|
          expect(
            described_class.for(environment: env, container: container, workflow_definition: duo_developer_flow)
          ).not_to eq(:background)
        end
      end

      it 'returns nil for a nil environment' do
        expect(
          described_class.for(environment: nil, container: container, workflow_definition: duo_developer_flow)
        ).to be_nil
      end

      it 'evaluates the flag against the root ancestor for a project container' do
        project = create(:project, group: container)

        expect(
          described_class.for(environment: 'web', container: project, workflow_definition: duo_developer_flow)
        ).to eq(:background)
      end
    end

    context 'when the background-governance flag is disabled' do
      before do
        stub_feature_flags(duo_workflow_background_tool_governance: false)
      end

      it 'returns nil even for an allowlisted background flow' do
        expect(
          described_class.for(environment: 'web', container: container, workflow_definition: duo_developer_flow)
        ).to be_nil
      end
    end

    context 'for local environments' do
      it 'returns the environment as the surface' do
        %w[ide chat chat_partial].each do |env|
          expect(described_class.for(environment: env, container: container)).to eq(env.to_sym)
        end
      end

      it 'returns nil for an environment outside the local allowlist' do
        expect(described_class.for(environment: 'external', container: container)).to be_nil
      end

      it 'never resolves a background environment as a local surface' do
        # `web` with a non-allowlisted flow falls through background resolution
        # and must stay on the caller's default, not become a local surface.
        expect(
          described_class.for(environment: 'web', container: container, workflow_definition: 'security_review/v1')
        ).to be_nil
      end

      it 'returns nil for a blank environment' do
        expect(described_class.for(environment: '', container: container)).to be_nil
      end

      it 'evaluates the flag against the root ancestor for a project container' do
        project = create(:project, group: container)

        expect(described_class.for(environment: 'ide', container: project)).to eq(:ide)
      end

      context 'when the local-governance flag is disabled' do
        before do
          stub_feature_flags(duo_workflow_local_tool_governance: false)
        end

        it 'returns UNGOVERNED, not nil, so callers cannot default it to web' do
          expect(described_class.for(environment: 'ide', container: container))
            .to eq(described_class::UNGOVERNED)
        end

        it 'does not affect background resolution' do
          expect(
            described_class.for(environment: 'web', container: container, workflow_definition: duo_developer_flow)
          ).to eq(:background)
        end
      end
    end
  end

  describe '.ungoverned?' do
    it 'recognises only the sentinel', :aggregate_failures do
      expect(described_class.ungoverned?(described_class::UNGOVERNED)).to be(true)
      expect(described_class.ungoverned?(:web)).to be(false)
      expect(described_class.ungoverned?(:ide)).to be(false)
      expect(described_class.ungoverned?(nil)).to be(false)
    end
  end

  # Guards the shape of gitlab-org/gitlab#622602: `nil` must stay distinguishable from
  # "this session must not be governed". Adding an environment to LOCAL_ENVIRONMENTS or
  # BACKGROUND_ENVIRONMENTS means adding a row here, which forces the author to state
  # what an unconfigured user on that surface should experience.
  describe 'surface resolution matrix' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:matrix_group) { create(:group) }
    let_it_be(:matrix_flow) { 'developer/v1' }

    where(:environment, :definition, :local_flag, :background_flag, :expected) do
      'web'          | nil | false | false | nil
      'web'          | ref(:matrix_flow) | false | true  | :background
      'web'          | ref(:matrix_flow) | false | false | nil
      'ambient'      | nil            | false | false | nil
      'ide'          | nil            | false | false | :ungoverned
      'ide'          | nil            | true  | false | :ide
      'chat'         | nil            | false | false | :ungoverned
      'chat'         | nil            | true  | false | :chat
      'chat_partial' | nil            | false | false | :ungoverned
      'chat_partial' | nil            | true  | false | :chat_partial
      'ambient'      | ref(:matrix_flow) | false | true | :background
      'external'     | nil            | false | false | nil
      nil            | nil            | false | false | nil
      'ide'          | nil            | true  | true  | :ide
      'web'          | ref(:matrix_flow) | true | true | :background
    end

    with_them do
      before do
        stub_feature_flags(
          duo_workflow_local_tool_governance: local_flag,
          duo_workflow_background_tool_governance: background_flag
        )
      end

      it 'resolves as stated' do
        expect(
          described_class.for(
            environment: environment, container: matrix_group, workflow_definition: definition
          )
        ).to eq(expected)
      end
    end
  end
end
