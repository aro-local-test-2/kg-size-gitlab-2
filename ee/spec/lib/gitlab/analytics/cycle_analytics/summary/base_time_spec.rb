# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Analytics::CycleAnalytics::Summary::BaseTime, feature_category: :devops_reports do
  describe 'stage_event_hash_id assignment with use_aggregated_data_collector', :aggregate_failures do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:user) { create(:user) }

    let(:stage) { Analytics::CycleAnalytics::Stage.new(namespace: group) }
    let(:options) { { from: 5.days.ago, use_aggregated_data_collector: true } }
    let(:events_hash_code) { Digest::SHA256.hexdigest("#{lead_time_start_hash}-#{lead_time_end_hash}") }
    let(:lead_time_start_hash) { Gitlab::Analytics::CycleAnalytics::StageEvents[:issue_created].new({}).hash_code }
    let(:lead_time_end_hash) { Gitlab::Analytics::CycleAnalytics::StageEvents[:issue_closed].new({}).hash_code }

    subject(:summary) { Gitlab::Analytics::CycleAnalytics::Summary::LeadTime.new(stage: stage, current_user: user, options: options) }

    context 'when a matching hash exists in the same organization' do
      let!(:hash_record) do
        Analytics::CycleAnalytics::StageEventHash.create!(
          organization: organization,
          hash_sha256: events_hash_code
        )
      end

      it 'assigns the hash from the correct organization' do
        summary

        expect(stage.stage_event_hash_id).to eq(hash_record.id)
      end
    end

    context 'when a matching hash exists only in a different organization' do
      let_it_be(:other_organization) { create(:organization) }

      let!(:other_hash_record) do
        Analytics::CycleAnalytics::StageEventHash.create!(
          organization: other_organization,
          hash_sha256: events_hash_code
        )
      end

      it 'does not assign the hash from another organization' do
        summary

        expect(stage.stage_event_hash_id).to be_nil
      end
    end

    context 'when matching hashes exist in multiple organizations' do
      let_it_be(:other_organization) { create(:organization) }

      let!(:correct_hash) do
        Analytics::CycleAnalytics::StageEventHash.create!(
          organization: organization,
          hash_sha256: events_hash_code
        )
      end

      let!(:wrong_hash) do
        Analytics::CycleAnalytics::StageEventHash.create!(
          organization: other_organization,
          hash_sha256: events_hash_code
        )
      end

      it 'assigns the hash from the correct organization' do
        summary

        expect(stage.stage_event_hash_id).to eq(correct_hash.id)
        expect(stage.stage_event_hash_id).not_to eq(wrong_hash.id)
      end
    end
  end
end
