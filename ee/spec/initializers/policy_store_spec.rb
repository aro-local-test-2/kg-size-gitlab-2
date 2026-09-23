# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'policy_store initializer', feature_category: :security_policy_management do
  it 'wires the facade to the ActiveRecord repository' do
    expect(Gitlab::PolicyStore.configuration.repository)
      .to be_a(Govern::PolicyStore::ActiveRecordPolicyRepository)
  end

  it 'wires the facade to the ActiveRecord evaluation recorder' do
    expect(Gitlab::PolicyStore.configuration.evaluation_recorder)
      .to be_a(Govern::PolicyStore::ActiveRecordEvaluationRecorder)
  end
end
