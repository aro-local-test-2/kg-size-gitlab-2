# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Members::AddedWorker, feature_category: :seat_cost_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user) }

  let(:members_added_event) do
    ::Members::MembersAddedEvent.new(
      data: { source_id: group.id, source_type: group.class.name, invited_user_ids: [user.id] }
    )
  end

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  describe '#handle_event' do
    it 'does nothing' do
      expect { consume_event(subscriber: described_class, event: members_added_event) }.not_to raise_error
    end
  end
end
