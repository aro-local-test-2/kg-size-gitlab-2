# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Cd::DefinitionStepsResolver, feature_category: :continuous_delivery do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:application) { create(:cd_application, organization: organization) }

  let(:definition) do
    <<~YAML
      steps:
        - type: com.gitlab.cd.steps.stage
          name: production
          steps:
            - type: com.gitlab.cd.argo.canary.deploy
              environment: production
              services:
                - name: web
                  weight: 100
        - type: com.gitlab.cd.steps.wait
          seconds: 30
    YAML
  end

  let(:flow_definition) { create(:cd_application_flow_definition, application: application, definition: definition) }

  subject(:resolved) { resolve(described_class, obj: flow_definition, ctx: { current_user: user }) }

  # Cd::ApplicationFlowDefinition now validates its own definition against the flow schema on
  # save (see Cd::DeployDrivers::FlowDefinitionValidator), so a genuinely malformed/empty
  # definition can no longer be persisted through the normal factory path. These scenarios
  # simulate historical or corrupted data by writing straight to the file store, bypassing
  # that validation, the same way ee/spec/services/cd/rollouts/create_service_spec.rb does.
  def stub_definition_file(flow_definition, raw_definition)
    flow_definition.file.store!(CarrierWaveStringFile.new(raw_definition))
    flow_definition.remove_instance_variable(:@definition) if flow_definition.instance_variable_defined?(:@definition)
  end

  it 'returns the top-level nodes of the flow definition step tree' do
    expect(resolved.map(&:step_type)).to eq(%w[com.gitlab.cd.steps.stage com.gitlab.cd.steps.wait])
  end

  it "resolves a stage's nested steps and carries their raw environment name" do
    stage = resolved.first

    expect(stage.steps.size).to eq(1)
    expect(stage.steps.first).to have_attributes(
      step_type: 'com.gitlab.cd.argo.canary.deploy',
      environment_name: 'production',
      organization_id: organization.id
    )
  end

  context 'when the flow definition has no steps' do
    before do
      stub_definition_file(flow_definition, "steps: []\n")
    end

    it 'returns an empty list' do
      expect(resolved).to eq([])
    end
  end

  context 'when the flow definition is unparseable' do
    before do
      stub_definition_file(flow_definition, "steps: [\n")
    end

    it 'returns nil rather than raising' do
      expect(resolved).to be_nil
    end
  end

  context 'when the flow definition file is missing from the file store' do
    before do
      allow(flow_definition).to receive(:definition).and_raise(Errno::ENOENT)
    end

    it 'returns nil and tracks the exception' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
        instance_of(Errno::ENOENT),
        flow_definition_id: flow_definition.id
      )

      expect(resolved).to be_nil
    end
  end

  context 'when the ai_native_deploy feature flag is disabled' do
    before do
      stub_feature_flags(ai_native_deploy: false)
    end

    it 'returns nil' do
      expect(resolved).to be_nil
    end
  end
end
