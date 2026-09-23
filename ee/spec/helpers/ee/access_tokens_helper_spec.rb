# frozen_string_literal: true

require "spec_helper"

RSpec.describe EE::AccessTokensHelper, feature_category: :system_access do
  describe '#expires_at_field_data', :freeze_time do
    context 'when personal_access_token_max_expiry_date is nil' do
      before do
        allow(helper).to receive_messages(
          # The `false` condition is tested in the CE test.
          personal_access_token_expiration_policy_licensed?: true,
          personal_access_token_expiration_policy_enabled?: true,
          personal_access_token_max_expiry_date: nil,
          max_expiration_days: 365
        )
      end

      it 'returns expected hash' do
        expect(helper.expires_at_field_data).to eq({
          min_date: 1.day.from_now.iso8601,
          max_date: nil,
          max_expiration_days: 365,
          pat_expiration_required: 'true'
        })
      end
    end

    context 'when personal_access_token_max_expiry_date is a date' do
      before do
        travel_to Date.new(2022, 2, 2)

        allow(helper).to receive_messages(
          personal_access_token_expiration_policy_enabled?: true, # The `false` condition is tested in the CE test.
          personal_access_token_max_expiry_date: Time.new(2022, 3, 2, 10, 30, 45, 'UTC'),
          max_expiration_days: 25
        )
      end

      it 'returns expected hash' do
        expect(helper.expires_at_field_data).to eq({
          min_date: '2022-02-03T00:00:00Z',
          max_date: '2022-03-02T10:30:45Z',
          max_expiration_days: 25,
          pat_expiration_required: 'true'
        })
      end
    end

    context 'when the EE expiry policy is enabled but require_personal_access_token_expiry is off' do
      before do
        travel_to Date.new(2022, 2, 2)
        stub_application_setting(require_personal_access_token_expiry: false)

        allow(helper).to receive_messages(
          personal_access_token_expiration_policy_enabled?: true,
          personal_access_token_max_expiry_date: Time.new(2022, 3, 2, 10, 30, 45, 'UTC'),
          max_expiration_days: 25
        )
      end

      it 'reports max_date from the EE policy while expiration remains optional' do
        expect(helper.expires_at_field_data).to eq({
          min_date: '2022-02-03T00:00:00Z',
          max_date: '2022-03-02T10:30:45Z',
          max_expiration_days: 25,
          pat_expiration_required: 'false'
        })
      end
    end
  end

  describe '#max_expiration_days' do
    subject { helper.send(:max_expiration_days) }

    let(:instance_level_max_personal_access_token_lifetime) { nil }
    let(:user) { build(:user) }

    before do
      allow(helper).to receive(:current_user) { user }
      stub_application_setting(max_personal_access_token_lifetime: instance_level_max_personal_access_token_lifetime)
    end

    context 'when the `personal_access_token_expiration_policy` feature is not licensed' do
      before do
        stub_licensed_features(personal_access_token_expiration_policy: false)
      end

      # Falls through to the CE implementation.
      it { is_expected.to eq(::PersonalAccessToken.max_expiration_lifetime_in_days) }
    end

    context 'when the `personal_access_token_expiration_policy` feature is licensed' do
      before do
        stub_licensed_features(personal_access_token_expiration_policy: true)
      end

      context 'when the instance has a max token lifetime configured' do
        let(:instance_level_max_personal_access_token_lifetime) { 20 }

        it { is_expected.to eq(20) }
      end

      context 'when the instance does not have a max token lifetime configured' do
        # Falls through to the CE implementation because the EE expiration policy is not enabled.
        it { is_expected.to eq(::PersonalAccessToken.max_expiration_lifetime_in_days) }
      end
    end
  end

  describe '#personal_access_token_data' do
    let_it_be(:user) { build_stubbed(:user) }

    subject(:data) { helper.personal_access_token_data({})[:access_token] }

    before do
      allow(helper).to receive(:current_user).and_return(user)
    end

    it 'returns agentic_available true when the permissions assistant agent is available' do
      expect(user).to receive(:foundational_agent_available?).with('duo_permissions_assistant').and_return(true)
      expect(data[:agentic_available]).to eq('true')
    end

    it 'returns agentic_available false when the permissions assistant agent is not available' do
      expect(user).to receive(:foundational_agent_available?).with('duo_permissions_assistant').and_return(false)
      expect(data[:agentic_available]).to eq('false')
    end
  end

  describe '#show_group_access_tokens_premium_offer?' do
    let_it_be(:user) { build_stubbed(:user) }
    let_it_be(:group) { build_stubbed(:group) }

    before do
      allow(helper).to receive(:current_user).and_return(user)
      allow(helper).to receive(:can?).with(user, :create_resource_access_tokens, group).and_return(false)
      allow(helper).to receive(:can?).with(user, :read_billing, group.root_ancestor).and_return(true)
      allow(::Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(true)
      allow(group.root_ancestor).to receive(:plan_name_for_upgrading).and_return(::Plan::FREE)
    end

    it 'returns true for a Free SaaS group owner who cannot create tokens' do
      expect(helper.show_group_access_tokens_premium_offer?(group)).to be(true)
    end

    it 'returns false when the user can already create tokens' do
      allow(helper).to receive(:can?).with(user, :create_resource_access_tokens, group).and_return(true)

      expect(helper.show_group_access_tokens_premium_offer?(group)).to be(false)
    end

    it 'returns false when not on SaaS' do
      allow(::Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)

      expect(helper.show_group_access_tokens_premium_offer?(group)).to be(false)
    end

    it 'returns false when the user cannot read billing' do
      allow(helper).to receive(:can?).with(user, :read_billing, group.root_ancestor).and_return(false)

      expect(helper.show_group_access_tokens_premium_offer?(group)).to be(false)
    end

    it 'returns false when the group is on a paid plan' do
      allow(group.root_ancestor).to receive(:plan_name_for_upgrading).and_return(::Plan::PREMIUM)

      expect(helper.show_group_access_tokens_premium_offer?(group)).to be(false)
    end

    context 'when the user is an Owner of a subgroup but not of the root group' do
      let(:root_group) { build_stubbed(:group) }
      let(:subgroup) { build_stubbed(:group, parent: root_group) }

      before do
        allow(subgroup).to receive(:root_ancestor).and_return(root_group)
        allow(helper).to receive(:can?).with(user, :create_resource_access_tokens, subgroup).and_return(false)
        allow(helper).to receive(:can?).with(user, :read_billing, root_group).and_return(false)
      end

      it 'returns false because Explore plans and Upgrade target the root group billing page' do
        expect(helper.show_group_access_tokens_premium_offer?(subgroup)).to be(false)
      end
    end
  end

  describe '#show_project_access_token_upgrade_card?' do
    let(:group) { build_stubbed(:group) }
    let(:project) { build_stubbed(:project, group: group) }
    let(:user) { build_stubbed(:user) }

    subject { helper.show_project_access_token_upgrade_card?(project) }

    before do
      allow(helper).to receive(:current_user).and_return(user)
      stub_saas_features(gitlab_com_subscriptions: true)
      allow(project).to receive(:root_ancestor).and_return(group)
      allow(group).to receive(:licensed_feature_available?).with(:resource_access_token).and_return(false)
      allow(helper).to receive(:can?).with(user, :read_billing, group).and_return(true)
      allow(helper).to receive(:can?).with(user, :create_resource_access_tokens, project).and_return(false)
    end

    it { is_expected.to be(true) }

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the project has no group' do
      it 'returns false' do
        expect(helper.show_project_access_token_upgrade_card?(build_stubbed(:project))).to be(false)
      end
    end

    context 'when the user can create tokens' do
      before do
        allow(helper).to receive(:can?).with(user, :create_resource_access_tokens, project).and_return(true)
      end

      it { is_expected.to be(false) }
    end

    context 'when the user cannot read billing' do
      before do
        allow(helper).to receive(:can?).with(user, :read_billing, group).and_return(false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the resource access token feature is licensed' do
      before do
        allow(group).to receive(:licensed_feature_available?).with(:resource_access_token).and_return(true)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#project_access_token_upgrade_card_data' do
    let(:group) { build_stubbed(:group) }
    let(:project) { build_stubbed(:project, group: group) }

    let(:premium_plan) { double('plan', code: ::Plan::PREMIUM, id: 'premium-id') } # rubocop:disable RSpec/VerifiedDoubles -- lightweight plan stub

    subject(:data) { helper.project_access_token_upgrade_card_data(project) }

    before do
      allow(project).to receive(:root_ancestor).and_return(group)
      allow(group).to receive(:plan_name_for_upgrading).and_return('free')
    end

    def stub_plans(plans)
      allow_next_instance_of(::GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
        allow(service).to receive(:execute).and_return(plans)
      end
    end

    it 'returns the docs and explore plans URLs' do
      stub_plans([premium_plan])

      expect(data[:docs_url]).to eq(help_page_path('user/project/settings/project_access_tokens.md'))
      expect(data[:explore_plans_url])
        .to eq(group_billings_path(group, source: 'project-access-tokens-upgrade-card'))
    end

    it 'builds the Premium checkout URL when the plan is found' do
      stub_plans([premium_plan])

      expect(data[:upgrade_url]).to include('plan_id=premium-id')
    end

    it 'falls back to the pricing page when no Premium plan is returned' do
      stub_plans([])

      expect(data[:upgrade_url]).to eq(::Gitlab::Routing.url_helpers.promo_pricing_url)
    end
  end
end
