# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Security::Parsers::Sarif::ReportTypeInference, feature_category: :vulnerability_management do
  describe '.infer_from' do
    let(:result) { {} }
    let(:rule) { {} }
    let(:semantic_ids) do
      Gitlab::Security::Parsers::Sarif::IdentifierExtractor.semantic_identifiers(
        result: result, rule: rule
      )
    end

    subject(:infer_from) { described_class.infer_from(semantic_ids: semantic_ids) }

    context 'when there is a CVE identifier' do
      let(:result) { { 'ruleId' => 'CVE-2021-44228' } }

      it 'infers dependency_scanning from a CVE in ruleId' do
        expect(infer_from).to eq(:dependency_scanning)
      end
    end

    context 'when there is a secret CWE' do
      described_class::SECRET_CWES.each do |cwe|
        context "for CWE-#{cwe}" do
          let(:rule) { { 'properties' => { 'tags' => ["CWE-#{cwe}"] } } }

          it "infers secret_detection" do
            expect(infer_from).to eq(:secret_detection)
          end
        end
      end
    end

    context 'when there is a non-secret CWE' do
      let(:rule) { { 'properties' => { 'tags' => ['CWE-89'] } } }

      it 'infers sast for a non-secret CWE' do
        expect(infer_from).to eq(:sast)
      end
    end

    context 'when no identifiers are present' do
      it 'defaults to sast' do
        expect(infer_from).to eq(:sast)
      end
    end
  end
end
