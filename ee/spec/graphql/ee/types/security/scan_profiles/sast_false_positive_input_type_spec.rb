# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::SastFalsePositiveInputType, feature_category: :security_testing_configuration do
  specify { expect(described_class.graphql_name).to eq('SecurityScanProfileSastFalsePositiveInput') }

  it 'has the expected arguments' do
    expect(described_class.arguments.keys).to match_array(%w[severityLevel cweClasses runMode])
  end

  it 'restricts cweClasses to CWE identifiers' do
    expect(described_class.arguments['cweClasses'].type.of_type.of_type).to eq(Types::Security::CweIdentifierType)
  end
end
