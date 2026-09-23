# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::Scanners, feature_category: :secret_detection do
  describe 'constants' do
    it 'defines expected constants' do
      expect(described_class::GITLEAKS).to eq(:gitleaks_scanner)
      expect(described_class::GSS).to eq(:gss_scanner)
      expect(described_class::ALL).to eq([:gitleaks_scanner, :gss_scanner])
    end
  end

  describe '.target_for_finding' do
    let(:finding) { instance_double(Security::Finding, identifier_types: identifier_types) }

    context 'when the finding has a GSS rule identifier type' do
      let(:identifier_types) { [Security::SecretDetection::RuleIdentifiers::GSS_TYPE] }

      it 'returns the GSS scanner' do
        expect(described_class.target_for_finding(finding)).to eq(described_class::GSS)
      end
    end

    context 'when the finding has both rule identifier types' do
      let(:identifier_types) do
        [
          Security::SecretDetection::RuleIdentifiers::GITLEAKS_TYPE,
          Security::SecretDetection::RuleIdentifiers::GSS_TYPE
        ]
      end

      it 'returns the GSS scanner' do
        expect(described_class.target_for_finding(finding)).to eq(described_class::GSS)
      end
    end

    context 'when the finding has only the gitleaks rule identifier type' do
      let(:identifier_types) { [Security::SecretDetection::RuleIdentifiers::GITLEAKS_TYPE] }

      it 'returns the gitleaks scanner' do
        expect(described_class.target_for_finding(finding)).to eq(described_class::GITLEAKS)
      end
    end

    context 'when the finding has no identifier types' do
      let(:identifier_types) { [] }

      it 'returns the gitleaks scanner' do
        expect(described_class.target_for_finding(finding)).to eq(described_class::GITLEAKS)
      end
    end
  end
end
