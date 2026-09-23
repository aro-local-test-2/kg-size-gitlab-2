# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::ContributionAnalytics::ClickHouseDataCollector, feature_category: :value_stream_management do
  let_it_be(:root) { create(:group) }
  let_it_be(:group) { create(:group, parent: root) }

  let(:collector) { described_class.new(group: group, from: 1.week.ago.beginning_of_day, to: Time.current.end_of_day) }

  describe '#totals_by_author_target_type_action' do
    it 'annotates the ClickHouse query with the namespace' do
      comment = nil

      allow(ClickHouse::Client).to receive(:select) do
        comment = Gitlab::Json::SafeParser.parse(ClickHouse::HttpClient.log_comment)
        []
      end

      collector.totals_by_author_target_type_action

      expect(comment).to include('root_namespace_id' => root.id)
    end
  end
end
