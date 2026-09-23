# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::ConnectionTestResult, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'passed' => true,
      'http_status' => 200,
      'last_health_status' => 'healthy',
      'last_health_checked_at' => '2026-08-20T10:00:00Z'
    }
  end

  subject(:test_result) { described_class.new(attributes) }

  describe 'documented readers' do
    it 'exposes every documented field from the parsed response hash', :aggregate_failures do
      expect(test_result.passed).to be(true)
      expect(test_result.http_status).to eq(200)
      expect(test_result.last_health_status).to eq('healthy')
      expect(test_result.last_health_checked_at).to eq(DateTime.iso8601('2026-08-20T10:00:00Z'))
    end
  end

  describe 'a probe that failed in transport' do
    let(:attributes) { super().merge('passed' => false, 'http_status' => nil) }

    it 'reports the failed verdict and a nil upstream status', :aggregate_failures do
      expect(test_result.passed).to be(false)
      expect(test_result.http_status).to be_nil
    end

    it 'still reports the stored health status, which one failure need not have moved' do
      expect(test_result.last_health_status).to eq('healthy')
    end
  end

  describe 'a repository no probe has run against' do
    let(:attributes) { { 'passed' => false, 'http_status' => nil, 'last_health_status' => 'unknown' } }

    it 'exposes the unknown status and a nil check timestamp', :aggregate_failures do
      expect(test_result.last_health_status).to eq('unknown')
      expect(test_result.last_health_checked_at).to be_nil
    end
  end

  describe 'a passed value that is not a boolean' do
    let(:attributes) { super().merge('passed' => 'true') }

    it 'reads as not passed, so only a boolean true reports a reachable upstream' do
      expect(test_result.passed).to be(false)
    end
  end

  describe 'unknown-field tolerance' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'ignored') }

    it 'still exposes every documented field and defines no reader for undocumented keys', :aggregate_failures do
      expect(test_result.passed).to be(true)
      expect(test_result.last_health_status).to eq('healthy')
      expect(test_result).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'an unrecognized health status' do
    let(:attributes) { super().merge('last_health_status' => 'degraded') }

    it 'passes the value through raw rather than raising' do
      expect(test_result.last_health_status).to eq('degraded')
    end
  end

  describe 'timestamp coercion' do
    context 'when the timestamp is not parseable' do
      let(:attributes) { super().merge('last_health_checked_at' => 'not-a-timestamp') }

      it 'returns nil rather than raising' do
        expect(test_result.last_health_checked_at).to be_nil
      end
    end

    context 'when the timestamp is not a string' do
      let(:attributes) { super().merge('last_health_checked_at' => 12345) }

      it 'returns nil rather than raising' do
        expect(test_result.last_health_checked_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:test_result) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(test_result.passed).to be(false)
      expect(test_result.http_status).to be_nil
      expect(test_result.last_health_status).to be_nil
      expect(test_result.last_health_checked_at).to be_nil
    end
  end
end
