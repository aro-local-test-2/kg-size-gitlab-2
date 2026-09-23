# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ScanProfileTriggerType'], feature_category: :security_testing_configuration do
  let(:published) { described_class.values.values.map(&:value) }

  it 'publishes an explicit set of trigger types' do
    expect(published).to match_array(
      %w[default_branch_pipeline merge_request_pipeline git_push_event sbom_ingested
        sast_false_positive sast_vulnerability_resolution secret_detection_false_positive
        vulnerability_enrichment]
    )
  end
end
