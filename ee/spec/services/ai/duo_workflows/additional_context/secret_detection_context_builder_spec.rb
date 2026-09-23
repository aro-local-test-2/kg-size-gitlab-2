# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::SecretDetectionContextBuilder, feature_category: :duo_agent_platform do
  let(:schema_path) do
    Rails.root.join(
      'app/validators/json_schemas/agent_platform/agent_platform_secrets_fp_detection_context/1.0.0.json'
    )
  end

  let(:schema) { JSONSchemer.schema(schema_path) }

  let_it_be(:project) { create(:project) }
  let_it_be(:vulnerability) do
    create(:vulnerability, report_type: :secret_detection, project: project).tap do |v|
      create(:vulnerabilities_finding, :identifier,
        vulnerability: v,
        report_type: :secret_detection,
        project: project,
        raw_metadata: { 'raw_source_code_extract' => 'glpat-secret-token' }.to_json)
    end
  end

  let_it_be(:redacted_vulnerability) do
    create(:vulnerability, report_type: :secret_detection, project: project).tap do |v|
      create(:vulnerabilities_finding, :identifier,
        vulnerability: v,
        report_type: :secret_detection,
        project: project,
        raw_metadata: { 'raw_source_code_extract' => 'glpat-redacted-token' }.to_json)
    end
  end

  subject(:envelopes) { described_class.build(vulnerability) }

  context 'when the finding has a raw secret value' do
    it 'returns both legacy and typed envelopes, both valid against the schema', :aggregate_failures do
      expect(envelopes.map { |e| e["Category"] }).to contain_exactly(
        "secret_detection_context",
        "agent_platform_secrets_fp_detection_context"
      )

      envelopes.each do |envelope|
        fields = ::Gitlab::Json::SafeParser.parse(envelope["Content"])
        expect(schema.valid?(fields)).to be(true), schema.validate(fields).to_a.inspect
        expect(fields["secret_value"]).to eq("glpat-secret-token")
      end
    end
  end

  context 'when the finding secret is redacted' do
    subject(:envelopes) { described_class.build(redacted_vulnerability) }

    before do
      create(:vulnerability_representation_information, vulnerability: redacted_vulnerability, removed_from_code: true)
    end

    it { is_expected.to be_nil }
  end

  context 'when the finding has no token value' do
    let_it_be(:vulnerability) do
      create(:vulnerability, report_type: :secret_detection, project: project).tap do |v|
        create(:vulnerabilities_finding, :identifier,
          vulnerability: v,
          report_type: :secret_detection,
          project: project,
          raw_metadata: {}.to_json)
      end
    end

    it { is_expected.to be_nil }
  end
end
