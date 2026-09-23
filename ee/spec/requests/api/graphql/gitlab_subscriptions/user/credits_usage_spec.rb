# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CurrentUser.creditsUsage', feature_category: :consumables_cost_management do
  include GraphqlHelpers

  let_it_be(:guest) { create(:user) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:subgroup_member) { create(:user) }
  let_it_be(:project_member) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:service_account) { create(:user, :service_account) }
  let_it_be(:bot) { create(:user, :project_bot) }

  let_it_be_with_reload(:root_group) { create(:group, owners: owner, guests: guest) }
  let_it_be(:subgroup) { create(:group, parent: root_group, developers: subgroup_member) }
  let_it_be(:project) { create(:project, group: subgroup, developers: project_member) }

  let(:current_user) { guest }
  let(:namespace_path) { root_group.full_path }
  let(:query_arguments) { { namespace_path: namespace_path } }

  let(:query_fields) do
    [
      :enabled,
      :is_outdated_client,
      :start_date,
      :end_date,
      :credits_used,
      query_graphql_field(:daily_usage, {}, [:date, :credits_used]),
      query_graphql_field(:products, {}, [
        :id,
        :title,
        query_graphql_field(:flow_types, {}, [:id, :title])
      ]),
      query_graphql_field(:used_flow_types, {}, [:id, :title]),
      query_graphql_field(:blocked_status, {}, [:blocked, :cap_type])
    ]
  end

  let(:query) do
    graphql_query_for(
      :current_user,
      {},
      query_graphql_field(:credits_usage, query_arguments.compact, query_fields)
    )
  end

  let(:usage_for_user_ids) do
    ->(user_ids, **_kwargs) do
      {
        success: true,
        usersUsage: user_ids.map { |id| { userId: id, totalCreditsUsed: (id * 10.45).round(2) } }
      }
    end
  end

  let(:daily_usage_for_user_id) do
    ->(user_id, **_kwargs) do
      { success: true, dailyUsage: [{ date: '2025-10-01', creditsUsed: (user_id * 1.5).round(2) }] }
    end
  end

  # Records every per-user call the resolver makes, so specs can assert on the
  # user ids that actually reached the Customer Portal client.
  let(:usage_requests) { [] }

  let(:daily_usage_requests) { [] }

  # Records the date range each client was built with, so specs can assert on the
  # effective range after clamping rather than the raw arguments.
  let(:client_date_ranges) { [] }

  before do
    stub_licensed_features(group_usage_billing: true)

    allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
      client_date_ranges << { start_date: client.start_date, end_date: client.end_date }

      allow(client).to receive_messages(
        get_metadata: {
          success: true,
          subscriptionUsage: {
            startDate: '2025-10-01',
            endDate: '2025-10-31',
            enabled: true,
            isOutdatedClient: false
          }
        },
        get_products: {
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

      allow(client).to receive(:get_usage_for_user_ids) do |ids, **kwargs|
        usage_requests << { user_ids: ids, flow_types: kwargs[:flow_types] }
        usage_for_user_ids.call(ids, **kwargs)
      end

      allow(client).to receive(:get_daily_usage_for_user_id) do |user_id, **kwargs|
        daily_usage_requests << { user_id: user_id, flow_types: kwargs[:flow_types] }
        daily_usage_for_user_id.call(user_id, **kwargs)
      end

      allow(client).to receive(:get_used_flow_types_for_user_id) do |user_id|
        { success: true, usedFlowTypes: [{ id: "flow_for_#{user_id}", title: 'Chat' }] }
      end

      allow(client).to receive(:get_blocked_statuses) do |entity_ids|
        {
          success: true,
          blockedStatuses: entity_ids.map do |id|
            { entityId: id, blocked: id.to_i.even?, capType: id.to_i.even? ? 'FLAT_USER_CAP' : nil }
          end
        }
      end
    end
  end

  subject(:credits_usage) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:current_user, :credits_usage)
  end

  shared_examples 'no self-usage data' do
    it 'returns no usage data' do
      expect(credits_usage).to be_nil
    end
  end

  context 'on arguments' do
    let(:arguments) { GitlabSchema.types['CurrentUser'].fields['creditsUsage'].arguments }

    it 'accepts only the namespace and filter arguments' do
      expect(arguments.keys).to contain_exactly('namespacePath', 'startDate', 'endDate', 'flowTypes')
    end

    it 'exposes no argument that could name another user' do
      expect(arguments.keys.grep(/user/i)).to be_empty
    end

    it 'requires a namespace path' do
      expect(arguments['namespacePath'].type.to_type_signature).to eq('ID!')
    end
  end

  context 'when in GitLab.com', :saas_gitlab_com_subscriptions do
    describe 'self-scoping' do
      it "returns the current user's own usage" do
        expect(credits_usage['creditsUsed']).to eq((guest.id * 10.45).round(2))
      end

      it 'requests usage for the current user id only' do
        post_graphql(query, current_user: guest)

        expect(usage_requests).to contain_exactly({ user_ids: [guest.id], flow_types: nil })
      end

      it 'requests the daily series for the current user id only' do
        post_graphql(query, current_user: guest)

        expect(daily_usage_requests).to contain_exactly({ user_id: guest.id, flow_types: nil })
      end

      it "returns the current user's own daily series" do
        expect(credits_usage['dailyUsage']).to eq([
          { 'date' => '2025-10-01', 'creditsUsed' => (guest.id * 1.5).round(2) }
        ])
      end

      it 'scopes usedFlowTypes and blockedStatus to the current user' do
        expect(credits_usage['usedFlowTypes']).to match_array([{ 'id' => "flow_for_#{guest.id}", 'title' => 'Chat' }])
        expect(credits_usage['blockedStatus']).to eq(
          'blocked' => guest.id.even?,
          'capType' => guest.id.even? ? 'FLAT_USER_CAP' : nil
        )
      end

      context 'when another member queries the same namespace' do
        it 'returns each user only their own figure' do
          post_graphql(query, current_user: guest)
          guest_credits = graphql_data_at(:current_user, :credits_usage, :creditsUsed)

          post_graphql(query, current_user: owner)
          owner_credits = graphql_data_at(:current_user, :credits_usage, :creditsUsed)

          expect(guest_credits).to eq((guest.id * 10.45).round(2))
          expect(owner_credits).to eq((owner.id * 10.45).round(2))
        end
      end
    end

    describe 'membership' do
      context 'when the user is a direct guest of the root group' do
        let(:current_user) { guest }

        it 'returns their usage' do
          expect(credits_usage['creditsUsed']).to eq((guest.id * 10.45).round(2))
        end
      end

      context 'when the user is a member of a subgroup' do
        let(:current_user) { subgroup_member }

        it 'returns their usage' do
          expect(credits_usage['creditsUsed']).to eq((subgroup_member.id * 10.45).round(2))
        end
      end

      context 'when the user is only a project member' do
        let(:current_user) { project_member }

        it_behaves_like 'no self-usage data'
      end

      context 'when the user is not a member anywhere in the hierarchy' do
        let(:current_user) { non_member }

        it_behaves_like 'no self-usage data'
      end
    end

    describe 'non-human users' do
      context 'with a service account' do
        let(:current_user) { service_account }

        before_all do
          root_group.add_developer(service_account)
        end

        it_behaves_like 'no self-usage data'
      end

      context 'with a bot' do
        let(:current_user) { bot }

        before_all do
          root_group.add_developer(bot)
        end

        it_behaves_like 'no self-usage data'
      end
    end

    describe 'namespace requirements' do
      context 'when the namespace is a subgroup' do
        let(:namespace_path) { subgroup.full_path }
        let(:current_user) { subgroup_member }

        it_behaves_like 'no self-usage data'
      end

      context 'when the namespace does not exist' do
        let(:namespace_path) { 'does-not-exist' }

        it_behaves_like 'no self-usage data'
      end

      context 'when the group is not entitled to GitLab Credits' do
        before do
          stub_licensed_features(group_usage_billing: false)
        end

        it_behaves_like 'no self-usage data'
      end

      context 'when the group has an active gitlab_credits add-on purchase' do
        before do
          stub_licensed_features(group_usage_billing: false)
          create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :active, namespace: root_group)
        end

        it 'returns their usage' do
          expect(credits_usage['creditsUsed']).to eq((guest.id * 10.45).round(2))
        end
      end
    end

    describe 'feature flag' do
      context 'when user_gitlab_credits_dashboard is disabled' do
        before do
          stub_feature_flags(user_gitlab_credits_dashboard: false)
        end

        it_behaves_like 'no self-usage data'
      end

      context 'when enabled only for a different namespace' do
        let_it_be(:other_group) { create(:group) }

        before do
          stub_feature_flags(user_gitlab_credits_dashboard: other_group)
        end

        it_behaves_like 'no self-usage data'
      end
    end

    describe 'display_gitlab_credits_user_data' do
      context 'when the namespace setting is disabled' do
        before do
          root_group.namespace_settings.update!(display_gitlab_credits_user_data: false)
        end

        it 'still returns the self view' do
          expect(credits_usage['creditsUsed']).to eq((guest.id * 10.45).round(2))
        end
      end
    end

    describe 'usage data' do
      it 'returns the period metadata' do
        expect(credits_usage).to include(
          'enabled' => true,
          'isOutdatedClient' => false,
          'startDate' => '2025-10-01',
          'endDate' => '2025-10-31'
        )
      end

      it 'returns the product filter taxonomy' do
        expect(credits_usage['products']).to eq([
          {
            'id' => 'duo_agent_platform',
            'title' => 'GitLab Duo Agent Platform',
            'flowTypes' => [{ 'id' => 'chat', 'title' => 'Chat' }]
          }
        ])
      end

      context 'when the user has no usage' do
        let(:usage_for_user_ids) { ->(_user_ids, **_kwargs) { { success: true, usersUsage: [] } } }

        it 'returns a null creditsUsed rather than another figure' do
          expect(credits_usage['creditsUsed']).to be_nil
        end
      end

      context 'when the user has no usage in the range' do
        let(:daily_usage_for_user_id) { ->(_user_id, **_kwargs) { { success: true, dailyUsage: [] } } }

        it 'returns an empty daily series' do
          expect(credits_usage['dailyUsage']).to eq([])
        end
      end

      context 'with a flow type filter' do
        let(:query_arguments) { { namespace_path: namespace_path, flow_types: ['chat'] } }

        it 'passes the filter through to the client' do
          post_graphql(query, current_user: guest)

          expect(usage_requests).to contain_exactly({ user_ids: [guest.id], flow_types: ['chat'] })
        end

        it 'passes the filter through to the daily series' do
          post_graphql(query, current_user: guest)

          expect(daily_usage_requests).to contain_exactly({ user_id: guest.id, flow_types: ['chat'] })
        end
      end
    end

    describe 'date range validation' do
      context 'when end_date precedes start_date' do
        let(:query_arguments) do
          { namespace_path: namespace_path, start_date: '2025-10-31', end_date: '2025-10-01' }
        end

        it 'returns an argument error' do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to include(
            a_hash_including('message' => 'end_date must be after or equal to start_date')
          )
        end
      end

      context 'when the range exceeds one year' do
        let(:query_arguments) do
          { namespace_path: namespace_path, start_date: '2024-01-01', end_date: '2025-06-01' }
        end

        it 'returns an argument error' do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to include(
            a_hash_including('message' => 'Date range cannot exceed 1 year')
          )
        end
      end
    end

    describe 'effective date range' do
      let(:query_arguments) do
        { namespace_path: namespace_path, start_date: requested_start, end_date: requested_end }
      end

      let(:requested_start) { '2026-02-01' }
      let(:requested_end) { '2026-02-28' }

      subject(:effective_range) do
        post_graphql(query, current_user: current_user)

        client_date_ranges.last
      end

      context 'when the namespace has no subscription' do
        it 'passes the requested range through' do
          expect(effective_range).to eq(start_date: '2026-02-01', end_date: '2026-02-28')
        end
      end

      context 'when the subscription started before the requested start date' do
        before do
          create(:gitlab_subscription, namespace: root_group, start_date: '2026-01-01')
        end

        it 'passes the requested range through' do
          expect(effective_range).to eq(start_date: '2026-02-01', end_date: '2026-02-28')
        end
      end

      context 'when the subscription started after the requested start date' do
        before do
          create(:gitlab_subscription, namespace: root_group, start_date: '2026-02-10')
        end

        it 'clamps the start date up to the subscription start date' do
          expect(effective_range).to eq(start_date: '2026-02-10', end_date: '2026-02-28')
        end
      end

      context 'when the requested end date is in the future' do
        let(:requested_start) { Date.current.beginning_of_month.iso8601 }
        let(:requested_end) { Date.current.next_month.end_of_month.iso8601 }

        it 'clamps the end date down to today' do
          expect(effective_range).to eq(
            start_date: Date.current.beginning_of_month.iso8601,
            end_date: Date.current.iso8601
          )
        end
      end
    end
  end
end
