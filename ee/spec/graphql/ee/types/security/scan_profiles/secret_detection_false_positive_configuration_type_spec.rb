# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::SecretDetectionFalsePositiveConfigurationType, feature_category: :security_testing_configuration do
  it { expect(described_class.graphql_name).to eq('SecretDetectionFalsePositiveConfiguration') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(:severity_level, :run_mode)
  end
end
