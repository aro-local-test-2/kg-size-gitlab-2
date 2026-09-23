# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'admin/application_settings/_security_policies.html.haml', feature_category: :security_policy_management do
  let(:app_settings) { build(:application_setting) }

  before do
    assign(:application_setting, app_settings)
  end

  context 'when security_policies_v2 is enabled' do
    it 'renders the Policy Store experiment toggle' do
      render

      expect(rendered).to have_content('Enable the Policy Store experiment')
    end
  end

  context 'when security_policies_v2 is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it 'still renders the toggle, since the flag is now checked per organization, not instance-wide' do
      render

      expect(rendered).to have_content('Enable the Policy Store experiment')
    end
  end
end
