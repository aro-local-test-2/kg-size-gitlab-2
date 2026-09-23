# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['FunctionalVerificationCheckType'], feature_category: :duo_agent_platform do
  let(:expected_values) { %w[AGENTIC_CHAT] }

  subject { described_class.values.keys }

  it { is_expected.to match_array(expected_values) }
end
