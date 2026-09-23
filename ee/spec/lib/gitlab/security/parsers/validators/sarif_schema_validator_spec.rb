# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Security::Parsers::Validators::SarifSchemaValidator, feature_category: :vulnerability_management do
  subject(:validator) { described_class.new(report_data) }

  context 'with a valid SARIF 2.1.0 document' do
    let(:report_data) do
      Gitlab::Json.safe_parse(
        fixture_file('security_reports/sarif/valid.sarif.json', dir: 'ee')
      )
    end

    it { is_expected.to be_valid }
    it { expect(validator.errors).to be_empty }
  end

  context 'with an unsupported version' do
    let(:report_data) { { 'version' => '2.0.0', 'runs' => [] } }

    it { is_expected.not_to be_valid }
    it { expect(validator.errors.first).to match(/Unsupported SARIF version/) }
  end

  context 'with a nil version' do
    let(:report_data) { { 'runs' => [] } }

    it { is_expected.not_to be_valid }
    it { expect(validator.errors.first).to match(/Unsupported SARIF version/) }
  end

  context 'with a non-Hash input' do
    let(:report_data) { [] }

    it { is_expected.not_to be_valid }
    it { expect(validator.errors.first).to match(/Expected JSON object but received Array/) }
  end

  context 'with a schema-invalid document' do
    let(:report_data) { { 'version' => '2.1.0' } }

    it { is_expected.not_to be_valid }
  end

  shared_context 'with clean schema cache' do
    around do |example|
      Thread.current[:sarif_schema_validators] = nil

      example.run
    ensure
      Thread.current[:sarif_schema_validators] = nil
    end
  end

  describe '.schema_for' do
    include_context 'with clean schema cache'

    before do
      allow(JSONSchemer).to receive(:schema) do
        double
      end
    end

    context 'when it is called with the same version multiple times' do
      it 'returns the same instance' do
        schema_1 = described_class.schema_for('2.1.0')
        schema_2 = described_class.schema_for('2.1.0')

        expect(schema_1).to be(schema_2)
      end

      it 'parses the schema once' do
        described_class.schema_for('2.1.0')
        described_class.schema_for('2.1.0')

        expect(JSONSchemer).to have_received(:schema).once
      end
    end

    context 'when it is called with different versions' do
      it 'does not return the same instance' do
        schema_1 = described_class.schema_for('2.1.0')
        schema_2 = described_class.schema_for('2.1.1')

        expect(schema_1).not_to be(schema_2)
      end

      it 'parses each version once' do
        described_class.schema_for('2.1.0')
        described_class.schema_for('2.1.1')

        expect(JSONSchemer).to have_received(:schema).twice
      end
    end
  end

  describe 'schema reuse across instances' do
    include_context 'with clean schema cache'

    let(:valid_report) do
      Gitlab::Json.safe_parse(
        fixture_file('security_reports/sarif/valid.sarif.json', dir: 'ee')
      )
    end

    let(:invalid_report) { { 'version' => '2.1.0' } }

    before do
      allow(JSONSchemer).to receive(:schema).and_call_original
    end

    it 'parses the schema once for every validator of the same version' do
      3.times { described_class.new(valid_report).valid? }

      expect(JSONSchemer).to have_received(:schema)
        .with(described_class::SCHEMA_BASE_PATH.join('sarif-schema-2.1.0.json')).once
    end

    it 'validates each report on its own against the shared schema' do
      expect(described_class.new(valid_report)).to be_valid
      expect(described_class.new(invalid_report)).not_to be_valid
      expect(described_class.new(valid_report)).to be_valid
    end
  end
end
