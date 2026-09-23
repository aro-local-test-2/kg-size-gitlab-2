# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::Chat::AgentEvents::BaseEvent, feature_category: :duo_chat do
  describe '#metadata?' do
    it 'is false, so an event counts towards the answer unless it opts out' do
      expect(described_class.new({})).not_to be_metadata
    end
  end
end
