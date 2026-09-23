# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::SecretDetectionFalsePositiveInputType, feature_category: :security_testing_configuration do
  specify { expect(described_class.graphql_name).to eq('SecurityScanProfileSecretDetectionFalsePositiveInput') }

  it 'has the expected arguments' do
    expect(described_class.arguments.keys).to match_array(%w[severityLevel runMode])
  end
end
