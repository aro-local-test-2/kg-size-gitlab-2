# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::SastFalsePositiveConfigurationType, feature_category: :security_testing_configuration do
  it { expect(described_class.graphql_name).to eq('SastFalsePositiveConfiguration') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(:severity_level, :cwe_classes, :run_mode)
  end
end
