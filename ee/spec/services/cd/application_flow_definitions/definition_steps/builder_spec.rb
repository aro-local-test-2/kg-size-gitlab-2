# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::ApplicationFlowDefinitions::DefinitionSteps::Builder, feature_category: :continuous_delivery do
  let(:parsed) do
    {
      'steps' => [
        {
          'type' => 'com.gitlab.cd.steps.stage',
          'name' => 'production',
          'steps' => [
            {
              'type' => 'com.gitlab.cd.argo.canary.deploy',
              'environment' => 'production',
              'services' => [{ 'name' => 'nginx', 'weight' => 33 }]
            }
          ]
        },
        { 'type' => 'com.gitlab.cd.steps.wait', 'seconds' => 30 }
      ]
    }
  end

  let(:document) { Cd::ApplicationFlowDefinitions::Document.new(parsed) }
  let(:flow_definition) { instance_double(Cd::ApplicationFlowDefinition, organization_id: 42) }

  subject(:steps) do
    described_class.new(document: document, flow_definition: flow_definition).steps
  end

  it 'builds one step per top-level node, in flow order' do
    expect(steps.size).to eq(2)

    stage, wait = steps
    expect(stage).to have_attributes(
      path: '0', parent_path: nil, step_type: 'com.gitlab.cd.steps.stage', name: 'production')
    expect(wait).to have_attributes(path: '1', parent_path: nil, step_type: 'com.gitlab.cd.steps.wait')
  end

  it "nests a stage's children under its own steps, in order" do
    stage, _wait = steps

    expect(stage.steps.size).to eq(1)
    expect(stage.steps.first).to have_attributes(
      path: '0.0', parent_path: '0', step_type: 'com.gitlab.cd.argo.canary.deploy')
  end

  it 'returns no nested steps for a non-stage node' do
    _stage, wait = steps

    expect(wait.steps).to eq([])
  end

  it 'copies step-specific configuration into params' do
    stage, wait = steps
    deploy = stage.steps.first

    expect(deploy.params).to eq('services' => [{ 'name' => 'nginx', 'weight' => 33 }])
    expect(wait.params).to eq('seconds' => 30)
  end

  it "carries each step's raw environment name, resolved later by the GraphQL type" do
    stage, wait = steps
    deploy = stage.steps.first

    expect(stage.environment_name).to be_nil
    expect(deploy.environment_name).to eq('production')
    expect(wait.environment_name).to be_nil
  end

  it "carries the flow_definition's organization_id on every node, to batch-resolve environments by name" do
    stage, wait = steps
    deploy = stage.steps.first

    expect([stage, wait, deploy]).to all(have_attributes(organization_id: 42))
  end

  it 'carries the flow_definition on every node, for authorization' do
    stage, wait = steps
    deploy = stage.steps.first

    expect([stage, wait, deploy]).to all(have_attributes(flow_definition: flow_definition))
  end

  context 'when the document has no steps' do
    let(:parsed) { { 'steps' => [] } }

    it 'returns an empty tree' do
      expect(steps).to eq([])
    end
  end
end
