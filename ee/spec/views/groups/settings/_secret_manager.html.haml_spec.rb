# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/secret_manager', feature_category: :secrets_management do
  let(:group) { build_stubbed(:group) }

  before do
    assign(:group, group)
    # The mount data is asserted through its own path; here we only care that the
    # hide_inline_text local is threaded into the mount's data attribute.
    allow(view).to receive_messages(current_user: build_stubbed(:user), secrets_manager_available_for_group?: true,
      allow_secrets_manager_namespace_enrollment?: false, namespace_enrollment_data: {})
  end

  it 'threads hide_inline_text into the mount data attribute' do
    render partial: 'groups/settings/secret_manager', locals: { hide_inline_text: true }

    expect(rendered).to have_css('.js-group-secrets-manager-settings[data-hide-inline-text="true"]')
  end

  it 'defaults hide_inline_text to false' do
    render partial: 'groups/settings/secret_manager'

    expect(rendered).to have_css('.js-group-secrets-manager-settings[data-hide-inline-text="false"]')
  end
end
