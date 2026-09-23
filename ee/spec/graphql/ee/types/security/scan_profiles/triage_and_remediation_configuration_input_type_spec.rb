# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::TriageAndRemediationConfigurationInputType, feature_category: :security_testing_configuration do
  specify { expect(described_class.graphql_name).to eq('SecurityScanProfileTriageAndRemediationConfigurationInput') }

  it { expect(described_class.one_of?).to be(true) }

  it 'exposes one member per remediation trigger type' do
    expect(described_class.arguments.values.map(&:keyword))
      .to match_array(Security::ScanProfileTrigger::REMEDIATION_TRIGGER_TYPES.map(&:to_sym))
  end

  it 'reuses the dependency scanning post-processing input for the sbom_ingested trigger' do
    expect(described_class.arguments['sbomIngested'].type)
      .to eq(Types::Security::ScanProfiles::DependencyScanningPostProcessingConfigurationInputType)
  end
end
