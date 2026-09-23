# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Members::DestroyedWorker, feature_category: :seat_cost_management do
  let_it_be(:root_namespace) { create(:group) }
  let_it_be(:user) { create(:user) }

  let(:members_destroyed_event) do
    ::Members::DestroyedEvent.new(
      data: {
        root_namespace_id: root_namespace.id,
        source_id: root_namespace.id,
        source_type: root_namespace.class.name,
        user_id: user.id
      }
    )
  end

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  describe '#handle_event' do
    it 'does nothing' do
      expect { consume_event(subscriber: described_class, event: members_destroyed_event) }.not_to raise_error
    end
  end
end
