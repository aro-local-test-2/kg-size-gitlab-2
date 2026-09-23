# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Change DAP land default credits experiment', :js, :saas,
  feature_category: :activation do
  include StubRequests
  include SubscriptionPortalHelpers

  let_it_be(:user) { create(:user, :with_namespace, company: 'GitLab') }
  let_it_be_with_reload(:group) { create(:group, owners: user) }
  let_it_be(:project) { create(:project, group: group) }

  let(:current_organization) { user.organization }

  let_it_be(:subscription) { create(:gitlab_subscription, namespace: group, hosted_plan: nil, seats: 15) }

  before do
    stub_signing_key
    stub_application_setting(check_namespace_plan: true)
    stub_billing_plans(group.id, 'free')
    stub_subscription_monthly_commitment_request
    stub_experiments(change_dap_land_default_credits: { variant: variant.to_sym, assigned: true })

    sign_in(user)
  end

  # The Customers Portal provisions the credits by calling back into GitLab, so no click reaches
  # this. Driving the service is what the portal would do once the purchase completes.
  def provision_credits
    GitlabSubscriptions::AddOnPurchases::GitlabCom::ProvisionService.new(
      group,
      gitlab_credits: [{
        'started_on' => Date.current.to_s,
        'expires_on' => 1.year.from_now.to_date.to_s,
        'purchase_xid' => 'S-A00000001',
        'quantity' => 25,
        'trial' => false
      }]
    ).execute
  end

  shared_examples 'tracking the purchase credits funnel' do
    it 'emits every event the journey declares for its variant', :capture_snowplow_events do
      visit group_billings_path(group)

      # execute_script does not wait, so block on the Vue-rendered CTA before querying for it.
      find_by_testid('dap-monthly-credit-card-cta-button')

      # Clicking for real leaves for the Customers Portal, which cancels the background
      # request reporting the click. Only the tracking is asserted here; the URL itself is
      # covered by billing_plans_helper_spec.rb.
      page.execute_script(
        "document.querySelector('[data-testid=\"dap-monthly-credit-card-cta-button\"]').href = '#'"
      )

      click_link 'Purchase credits'

      provision_credits

      expect_snowplow_tracking_journey('change_dap_land_default_credits', variant: variant)
    end
  end

  using RSpec::Parameterized::TableSyntax

  where(:variant) { %w[candidate control] }

  with_them do
    it_behaves_like 'tracking the purchase credits funnel'
  end
end
