# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Security::PolicyConfigurationAssignedEvent, feature_category: :security_policy_management do
  let_it_be(:configuration) { create(:security_orchestration_policy_configuration) }

  describe '.build' do
    it 'returns a valid PolicyConfigurationAssignedEvent', :aggregate_failures do
      event = described_class.build(configuration: configuration)

      expect(event.event_category).to eq(:security_policy_management)
      expect(event.event_type).to eq(:policy_configuration_assigned)
      expect(event.event_data[:configuration_id]).to eq(configuration.id)
    end
  end

  it_behaves_like 'a cloud event with schema',
    valid_data: { configuration_id: 1 },
    missing_required: %i[configuration_id],
    invalid_types: { configuration_id: 'not_an_integer' }
end
