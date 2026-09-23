# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedulePolicy, feature_category: :code_suggestions do
  let_it_be(:schedule) { create(:ai_flow_schedule) }

  subject(:policy) { described_class.new(nil, schedule) }

  it 'delegates to ProjectPolicy' do
    delegations = policy.delegated_policies

    expect(delegations.values[0]).to match(an_instance_of(::ProjectPolicy))
  end
end
