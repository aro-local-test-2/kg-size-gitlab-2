# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::AccessTokens::GroupPremiumOfferComponent, :aggregate_failures, :saas, feature_category: :acquisition do
  let_it_be(:group) { build_stubbed(:group) }

  let(:premium_plan) { Hashie::Mash.new(code: ::Plan::PREMIUM, id: 2, name: 'Premium') }
  let(:plans_data) { [premium_plan] }

  before do
    allow(group).to receive(:plan_name_for_upgrading).and_return(::Plan::FREE)

    allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
      allow(service).to receive(:execute).and_return(plans_data)
    end
  end

  subject(:render) { render_inline(described_class.new(group: group)) }

  it 'renders the heading and body' do
    render

    expect(page).to have_content(s_('AccessTokens|Try group access tokens with Premium'))
    expect(page).to have_content('creation is not available on GitLab Free')
    expect(page).to have_content(s_('AccessTokens|You can still manage existing tokens.'))
  end

  it 'renders the upgrade CTA pointing at the purchase flow with tracking' do
    render

    button = page.find('[data-testid="upgrade-to-premium-button"]')

    expect(button).to have_content(s_('AccessTokens|Upgrade to Premium'))
    expect(button['href']).to include('gl_namespace_id')
    expect(button['data-event-tracking']).to eq('click_upgrade_to_premium_on_group_access_tokens')
  end

  context 'when the Premium plan is missing from the plans data' do
    let(:plans_data) { nil }

    it 'falls back to the pricing page for the upgrade CTA without raising' do
      render

      button = page.find('[data-testid="upgrade-to-premium-button"]')

      expect(button['href']).to eq(Gitlab::Routing.url_helpers.promo_pricing_url)
    end
  end

  it 'renders the explore plans CTA pointing at group billing with tracking' do
    render

    button = page.find('[data-testid="explore-plans-button"]')

    expect(button).to have_content(s_('AccessTokens|Explore plans'))
    expect(button['href']).to eq(
      Gitlab::Routing.url_helpers.group_billings_path(
        group.root_ancestor, source: described_class::UPGRADE_CARD_TRACKING_SOURCE
      )
    )
    expect(button['data-event-tracking']).to eq('click_explore_plans_on_group_access_tokens')
  end

  it 'links the docs from the body with tracking' do
    render

    link = page.find('a', text: 'Group access token')

    expect(link['href']).to include('group_access_tokens')
    expect(link['data-event-tracking']).to eq('click_learn_more_on_group_access_tokens')
  end
end
