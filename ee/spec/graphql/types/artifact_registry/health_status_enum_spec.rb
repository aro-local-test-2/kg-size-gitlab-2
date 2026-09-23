# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryHealthStatus'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryHealthStatus') }

  where(:artifact_registry_value, :graphql_value) do
    'unknown'   | 'UNKNOWN'
    'healthy'   | 'HEALTHY'
    'unhealthy' | 'UNHEALTHY'
  end

  with_them do
    it 'decodes the Artifact Registry health status' do
      expect(described_class.coerce_isolated_result(artifact_registry_value)).to eq(graphql_value)
    end
  end

  it 'declares no value outside the Artifact Registry contract' do
    expect(described_class.values.keys).to contain_exactly('UNKNOWN', 'HEALTHY', 'UNHEALTHY')
  end

  describe '.recognized_or_unknown' do
    where(:status, :resolved) do
      'unknown'   | 'unknown'
      'healthy'   | 'healthy'
      'unhealthy' | 'unhealthy'
    end

    with_them do
      it 'passes a declared status through unchanged' do
        expect(described_class.recognized_or_unknown(status)).to eq(resolved)
      end
    end

    # Coercion of an undeclared value would fail the whole response, so absorbing it
    # here is what keeps an Artifact Registry addition from breaking every read.
    it 'absorbs a status Artifact Registry added ahead of this enum' do
      expect(described_class.recognized_or_unknown('degraded')).to eq('unknown')
    end

    it 'resolves a missing status to unknown' do
      expect(described_class.recognized_or_unknown(nil)).to eq('unknown')
    end
  end
end
