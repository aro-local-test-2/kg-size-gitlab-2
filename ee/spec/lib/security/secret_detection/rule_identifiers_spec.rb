# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::RuleIdentifiers, feature_category: :secret_detection do
  describe 'constants' do
    it 'defines expected constants' do
      expect(described_class::GITLEAKS_TYPE).to eq('gitleaks_rule_id')
      expect(described_class::GSS_TYPE).to eq('gitlab_secret_scanner_rule_id')
    end
  end

  describe '.reported_by_gss?' do
    let(:finding) { instance_double(Security::Finding, identifier_types: identifier_types) }

    context 'when the finding has a GSS identifier type' do
      let(:identifier_types) { [described_class::GITLEAKS_TYPE, described_class::GSS_TYPE] }

      it 'returns true' do
        expect(described_class.reported_by_gss?(finding)).to be(true)
      end
    end

    context 'when the finding has only gitleaks rule identifier type' do
      let(:identifier_types) { [described_class::GITLEAKS_TYPE] }

      it 'returns false' do
        expect(described_class.reported_by_gss?(finding)).to be(false)
      end
    end

    context 'when the finding has no identifier types' do
      let(:identifier_types) { [] }

      it 'returns false' do
        expect(described_class.reported_by_gss?(finding)).to be(false)
      end
    end
  end
end
