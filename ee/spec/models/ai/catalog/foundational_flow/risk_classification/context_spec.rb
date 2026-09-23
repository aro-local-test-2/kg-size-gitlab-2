# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::Catalog::FoundationalFlow::RiskClassification::Context, feature_category: :duo_agent_platform do
  describe '.call' do
    subject(:context) { described_class.call(resource: resource) }

    let(:resource) { build_stubbed(:merge_request) }
    let(:domains) { ::Gitlab::Duo::RiskClassification::Domain.all }
    let(:payload) { context.fetch('agent_platform_risk_classification_context') }

    it 'sends every domain the flow answers a claim about' do
      expect(payload['domains'].pluck('name')).to match_array(domains.map(&:name))
      expect(payload['domains']).to all(include('description' => be_present))
    end

    it 'is valid against the agent_platform_risk_classification_context schema' do
      schema_path = Rails.root.join(
        'app/validators/json_schemas/agent_platform/agent_platform_risk_classification_context/1.0.0.json'
      )
      schema = JSONSchemer.schema(schema_path)

      expect(schema.valid?(payload)).to be(true), schema.validate(payload).to_a.inspect
    end
  end
end
