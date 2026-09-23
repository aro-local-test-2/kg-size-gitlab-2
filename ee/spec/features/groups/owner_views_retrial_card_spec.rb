# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Groups > Billing > re-trial card', :js, :saas,
  :with_namespace_eligible_trials, feature_category: :subscription_management do
  include SubscriptionPortalHelpers

  let_it_be(:user) { create(:user, :with_namespace) }
  let(:current_organization) { user.organization }
  let_it_be(:group) { create(:group, owners: user) }

  before do
    stub_signing_key
    stub_application_setting(check_namespace_plan: true)
    stub_billing_plans(group.id)
    stub_subscription_monthly_commitment_request

    # Dates must sit outside the end-of-trial modal's recently-expired window, or that modal
    # renders over the card and intercepts clicks. The :expired_trial trait is too recent.
    create(
      :gitlab_subscription, :free,
      namespace: group, trial: true,
      trial_starts_on: 200.days.ago, trial_ends_on: 170.days.ago
    )

    sign_in(user)
    visit group_billings_path(group)
  end

  it 'offers the card to an eligible owner' do
    expect(page).to have_testid('re-trial-card')
  end

  context 'when the saas_ultimate_retrial flag is disabled' do
    before do
      stub_feature_flags(saas_ultimate_retrial: false)

      visit group_billings_path(group)
    end

    it 'does not offer the card' do
      expect(page).to have_no_testid('re-trial-card')
    end
  end

  context 'when the owner takes the trial' do
    it 'starts the trial flow and tracks the click', :capture_snowplow_events do
      find_by_testid('re-trial-card-cta').click

      expect(page).to have_current_path(new_trial_path(namespace_id: group.id))

      wait_for_snowplow_event(action: 'click_start_trial_on_retrial_card_group_billing')
    end
  end

  context 'when the owner dismisses the card' do
    it 'tracks the dismissal', :capture_snowplow_events do
      find_by_testid('re-trial-card-dismiss').click

      expect(page).to have_no_testid('re-trial-card')

      wait_for_snowplow_event(action: 'dismiss_retrial_card_group_billing')
    end

    it 'keeps it dismissed on the next page load' do
      find_by_testid('re-trial-card-dismiss').click

      expect(page).to have_no_testid('re-trial-card')

      wait_for('callout dismissed') do
        Users::GroupCallout.where(
          user_id: user.id,
          group_id: group.id,
          feature_name: BillingPlansHelper::RETRIAL_CARD_CALLOUT
        ).exists?
      end

      visit group_billings_path(group)

      expect(page).to have_no_testid('re-trial-card')
    end
  end
end
