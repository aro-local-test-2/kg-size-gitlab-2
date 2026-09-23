# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'admin/gitlab_credits_dashboard/index.html.haml', feature_category: :consumables_cost_management do
  it 'renders the dashboard root element with CTA paths' do
    render

    expect(rendered).to have_selector(
      "#js-instance-usage-billing-dashboard" \
        "[data-upgrade-button-path='#{promo_pricing_url(query: { deployment: 'self-managed-deployment' })}']" \
        "[data-purchase-credits-path='#{subscription_portal_self_managed_purchase_credits_url}']"
    )
  end

  context 'when there is a billable license' do
    let(:license) { build(:license, starts_at: Date.new(2026, 3, 1)) }

    before do
      allow(License).to receive(:billable_license).and_return(license)
    end

    it 'renders the subscription start date' do
      render

      expect(rendered).to have_selector(
        "#js-instance-usage-billing-dashboard[data-subscription-start-date='2026-03-01']"
      )
    end
  end

  context 'when there is no billable license' do
    before do
      allow(License).to receive(:billable_license).and_return(nil)
    end

    it 'does not render a subscription start date' do
      render

      expect(rendered).not_to have_selector(
        "#js-instance-usage-billing-dashboard[data-subscription-start-date]"
      )
    end
  end
end
