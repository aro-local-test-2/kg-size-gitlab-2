# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::EventLogState, feature_category: :geo_replication do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_id) }
  end
end
