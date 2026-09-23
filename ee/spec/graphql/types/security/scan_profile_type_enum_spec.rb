# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['SecurityScanProfileType'], feature_category: :security_testing_configuration do
  let(:published) { described_class.values.values.map(&:value) }

  it 'publishes an explicit set of scan profile types' do
    expect(published).to match_array(
      %w[sast secret_detection container_scanning dependency_scanning dependency_scanning_post_processing
        triage_and_remediation]
    )
  end
end
