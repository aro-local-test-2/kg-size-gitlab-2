# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['DuoWorkflowStatus'], feature_category: :duo_agent_platform do
  it 'has specific fields' do
    expect(described_class.values.keys).to match_array(%w[
      CREATED RUNNING PAUSED FINISHED FAILED STOPPED
      INPUT_REQUIRED PLAN_APPROVAL_REQUIRED TOOL_CALL_APPROVAL_REQUIRED
    ])
  end
end
