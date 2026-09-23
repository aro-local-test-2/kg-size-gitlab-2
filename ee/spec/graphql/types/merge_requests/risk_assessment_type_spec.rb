# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MergeRequestRiskAssessment'], feature_category: :code_review_workflow do
  expected_fields = %i[
    status risk confidence risk_tier confidence_tier contributing_signals domain_tags missing_signals
    rationale assessed_at stale duo_workflow_id
  ]

  subject { described_class }

  it { is_expected.to have_graphql_fields(expected_fields) }

  it 'accepts :ai_workflows in its own object-level authorization scopes' do
    expect(described_class.authorization_scopes).to include(:ai_workflows)
  end
end
