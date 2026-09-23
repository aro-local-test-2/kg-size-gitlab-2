# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SubscriptionsUsage::User::CreditsUsage,
  feature_category: :consumables_cost_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:namespace) { create(:group) }

  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }
  let(:flow_types) { nil }

  let(:metadata_response) do
    {
      subscriptionUsage: {
        startDate: '2025-10-01',
        endDate: '2025-10-31',
        enabled: true,
        isOutdatedClient: false
      }
    }
  end

  subject(:credits_usage) do
    described_class.new(
      user: user,
      namespace: namespace,
      subscription_usage_client: client,
      flow_types: flow_types
    )
  end

  before do
    allow(client).to receive(:get_metadata).and_return(metadata_response)
  end

  describe 'period metadata' do
    it 'exposes the period and client state' do
      expect(credits_usage.enabled?).to be(true)
      expect(credits_usage.outdated_client?).to be(false)
      expect(credits_usage.start_date).to eq('2025-10-01')
      expect(credits_usage.end_date).to eq('2025-10-31')
    end

    context 'when the Customer Portal returns no metadata' do
      let(:metadata_response) { {} }

      it 'reports the feature as disabled rather than raising' do
        expect(credits_usage.enabled?).to be(false)
        expect(credits_usage.start_date).to be_nil
      end
    end
  end

  describe '#credits_used' do
    before do
      allow(client).to receive(:get_usage_for_user_ids).and_return(
        {
          success: true,
          usersUsage: [
            { userId: other_user.id, creditsUsed: 999.99, totalCreditsUsed: 999.99 },
            { userId: user.id, creditsUsed: 10.0, totalCreditsUsed: 12.34 }
          ]
        }
      )
    end

    it 'requests usage for the given user id only' do
      credits_usage.credits_used

      expect(client).to have_received(:get_usage_for_user_ids).with([user.id], flow_types: nil)
    end

    it "returns the user's own figure, not another user's" do
      expect(credits_usage.credits_used).to eq(12.34)
    end

    it 'returns the total consumed, not the allocation-only figure' do
      expect(credits_usage.credits_used).not_to eq(10.0)
    end

    it 'memoizes the client call' do
      2.times { credits_usage.credits_used }

      expect(client).to have_received(:get_usage_for_user_ids).once
    end

    context 'with a flow type filter' do
      let(:flow_types) { ['chat'] }

      it 'passes the filter to the client' do
        credits_usage.credits_used

        expect(client).to have_received(:get_usage_for_user_ids).with([user.id], flow_types: ['chat'])
      end
    end

    context 'when the response omits the user' do
      before do
        allow(client).to receive(:get_usage_for_user_ids).and_return(
          { success: true, usersUsage: [{ userId: other_user.id, totalCreditsUsed: 999.99 }] }
        )
      end

      it 'returns nil rather than falling back to another entry' do
        expect(credits_usage.credits_used).to be_nil
      end
    end

    context 'when the client call fails' do
      before do
        allow(client).to receive(:get_usage_for_user_ids).and_return({ success: false })
      end

      it 'returns nil' do
        expect(credits_usage.credits_used).to be_nil
      end
    end
  end

  describe '#daily_usage' do
    before do
      allow(client).to receive(:get_daily_usage_for_user_id).and_return(
        {
          success: true,
          dailyUsage: [
            { date: '2025-10-01', creditsUsed: 12.5 },
            { date: '2025-10-02', creditsUsed: 3.0 }
          ]
        }
      )
    end

    it 'requests the series for the given user id only' do
      credits_usage.daily_usage

      expect(client).to have_received(:get_daily_usage_for_user_id).with(user.id, flow_types: nil)
    end

    it 'builds the series scoped to the user for policy checks' do
      expect(credits_usage.daily_usage).to match([
        have_attributes(date: '2025-10-01', credits_used: 12.5, declarative_policy_subject: user),
        have_attributes(date: '2025-10-02', credits_used: 3.0, declarative_policy_subject: user)
      ])
    end

    it 'memoizes the client call' do
      2.times { credits_usage.daily_usage }

      expect(client).to have_received(:get_daily_usage_for_user_id).once
    end

    context 'with a flow type filter' do
      let(:flow_types) { ['chat'] }

      it 'passes the filter to the client' do
        credits_usage.daily_usage

        expect(client).to have_received(:get_daily_usage_for_user_id).with(user.id, flow_types: ['chat'])
      end
    end

    context 'when the response has a null series' do
      before do
        allow(client).to receive(:get_daily_usage_for_user_id).and_return({ success: true, dailyUsage: nil })
      end

      it 'returns an empty array' do
        expect(credits_usage.daily_usage).to eq([])
      end
    end

    context 'when the client call fails' do
      before do
        allow(client).to receive(:get_daily_usage_for_user_id).and_return({ success: false })
      end

      it 'returns an empty array' do
        expect(credits_usage.daily_usage).to eq([])
      end
    end
  end

  describe '#used_flow_types' do
    before do
      allow(client).to receive(:get_used_flow_types_for_user_id).and_return(
        { success: true, usedFlowTypes: [{ id: 'chat', title: 'Chat' }] }
      )
    end

    it 'requests flow types for the given user id only' do
      credits_usage.used_flow_types

      expect(client).to have_received(:get_used_flow_types_for_user_id).with(user.id)
    end

    it 'builds flow types scoped to the user for policy checks' do
      flow_type = credits_usage.used_flow_types.first

      expect(flow_type.id).to eq('chat')
      expect(flow_type.title).to eq('Chat')
      expect(flow_type.declarative_policy_subject).to eq(user)
    end

    context 'when the client call fails' do
      before do
        allow(client).to receive(:get_used_flow_types_for_user_id).and_return({ success: false })
      end

      it 'returns an empty array' do
        expect(credits_usage.used_flow_types).to eq([])
      end
    end
  end

  describe '#products' do
    before do
      allow(client).to receive(:get_products).and_return(
        {
          success: true,
          products: [
            {
              id: 'duo_agent_platform',
              title: 'GitLab Duo Agent Platform',
              creditsUsed: 987.65,
              flowTypes: [{ id: 'chat', title: 'Chat' }]
            }
          ]
        }
      )
    end

    it 'builds the product filter taxonomy' do
      product = credits_usage.products.first

      expect(product.id).to eq('duo_agent_platform')
      expect(product.title).to eq('GitLab Duo Agent Platform')
      expect(product.flow_types.map(&:id)).to eq(['chat'])
      expect(product.declarative_policy_subject).to eq(user)
    end

    it 'drops the subscription-wide creditsUsed figure' do
      expect(credits_usage.products.first.credits_used).to be_nil
    end

    context 'when the client call fails' do
      before do
        allow(client).to receive(:get_products).and_return({ success: false })
      end

      it 'returns an empty array' do
        expect(credits_usage.products).to eq([])
      end
    end
  end

  describe '#blocked_status' do
    before do
      allow(client).to receive(:get_blocked_statuses).and_return(
        {
          success: true,
          blockedStatuses: [
            { entityId: other_user.id.to_s, blocked: true, capType: 'FLAT_USER_CAP' },
            { entityId: user.id.to_s, blocked: false, capType: nil }
          ]
        }
      )
    end

    it 'requests the blocked status for the given user id only' do
      credits_usage.blocked_status

      expect(client).to have_received(:get_blocked_statuses).with([user.id.to_s])
    end

    it "returns the user's own status, not another user's" do
      expect(credits_usage.blocked_status.blocked).to be(false)
      expect(credits_usage.blocked_status.cap_type).to be_nil
      expect(credits_usage.blocked_status.declarative_policy_subject).to eq(user)
    end

    context 'when the response omits the user' do
      before do
        allow(client).to receive(:get_blocked_statuses).and_return(
          {
            success: true,
            blockedStatuses: [{ entityId: other_user.id.to_s, blocked: true, capType: 'FLAT_USER_CAP' }]
          }
        )
      end

      it 'returns nil rather than another entry' do
        expect(credits_usage.blocked_status).to be_nil
      end
    end

    context 'when the client call fails' do
      before do
        allow(client).to receive(:get_blocked_statuses).and_return({ success: false })
      end

      it 'returns nil' do
        expect(credits_usage.blocked_status).to be_nil
      end
    end
  end

  describe '#declarative_policy_subject' do
    it 'delegates authorization to the user the usage is scoped to' do
      expect(credits_usage.declarative_policy_subject).to eq(user)
    end
  end
end
