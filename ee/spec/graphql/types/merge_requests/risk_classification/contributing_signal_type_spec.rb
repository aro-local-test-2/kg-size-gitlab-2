# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MergeRequestRiskContributingSignal'], feature_category: :code_review_workflow do
  subject { described_class }

  it { is_expected.to have_graphql_fields(:signal, :label, :contribution, :detail) }

  it 'accepts :ai_workflows in its own object-level authorization scopes' do
    expect(described_class.authorization_scopes).to include(:ai_workflows)
  end
end
