# frozen_string_literal: true

require 'spec_helper'

# A URL fragment (e.g. #L7) is never sent to the server, so the JS re-applies it to the
# server-built form actions of the multi-step sign-in to carry it onto the destination.
#
# On SaaS with two-step sign-in the passkey button renders only after the username step, so the
# load-time fragment seeder misses it; sign_in_form.vue re-applies the fragment to the passkey
# form action instead.
#
# Selenium's current_url fragment handling is unreliable, so the landing fragment is read with
# `page.evaluate_script('window.location.hash')` rather than matched against current_url.
RSpec.describe 'Login preserves URL fragment through two-step passkey sign-in',
  :js, :saas_redirect_sign_in_when_login_not_found, :with_current_organization,
  :clean_gitlab_redis_sessions, feature_category: :system_access do
  include Features::TwoFactorHelpers

  include_context 'with a deep link that preserves the URL fragment'

  let(:user) { create(:user, organization: current_organization) }

  before do
    # two_step_sign_in is disabled by default in the suite (spec_helper.rb), so enable it explicitly.
    stub_feature_flags(two_step_sign_in: true)
    allow(WebAuthn.configuration.relying_party).to receive(:allowed_origins).and_return([app_id])
  end

  it 'lands on the deep link fragment after the passkey responds' do
    passkey = add_passkey(app_id, user)

    visit deep_link
    expect(page).to have_field('user_login')
    expect(page).to have_no_button(s_('PasskeyAuthentication|Passkey'))

    fill_in 'user_login', with: user.username
    click_button _('Continue')
    expect(page).to have_button(s_('PasskeyAuthentication|Passkey'))

    click_button s_('PasskeyAuthentication|Passkey')
    expect(page).to have_current_path(users_passkeys_sign_in_path, ignore_query: true)

    passkey.respond_to_webauthn_authentication

    expect_landed_on_deep_link
  end
end
