# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::NamespaceConnectionTestResult, feature_category: :artifact_registry do
  subject(:result) { described_class.new(attributes) }

  describe '#passed' do
    context 'when the attribute is true' do
      let(:attributes) { { 'passed' => true } }

      it { expect(result.passed).to be(true) }
    end

    context 'when the attribute is false' do
      let(:attributes) { { 'passed' => false } }

      it { expect(result.passed).to be(false) }
    end

    context 'when the attribute is absent' do
      let(:attributes) { {} }

      it 'is false rather than nil, so a hollow body never reads as a pass' do
        expect(result.passed).to be(false)
      end
    end
  end

  describe '#http_status' do
    context 'when the upstream answered' do
      let(:attributes) { { 'http_status' => 200 } }

      it { expect(result.http_status).to eq(200) }
    end

    context 'when no response arrived' do
      let(:attributes) { { 'http_status' => nil } }

      it { expect(result.http_status).to be_nil }
    end
  end

  context 'when initialized with nil' do
    let(:attributes) { nil }

    it 'reads as an empty, not-passed verdict', :aggregate_failures do
      expect(result.passed).to be(false)
      expect(result.http_status).to be_nil
    end
  end
end
