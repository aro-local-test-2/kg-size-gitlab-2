# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User manages environments', :js, :with_current_organization,
  feature_category: :continuous_delivery do
  include ListboxHelpers

  let_it_be(:user) { create(:user, :organization_owner, organizations: [current_organization]) }

  before do
    sign_in(user)
  end

  context 'when the ai_native_deploy feature flag is disabled' do
    before do
      stub_feature_flags(ai_native_deploy: false)
    end

    it 'renders a 404' do
      visit deploy_environments_organization_path(current_organization)

      expect(page).to have_content('Page not found')
    end
  end

  context 'when the ai_native_deploy feature flag is enabled' do
    context 'when creating a new environment' do
      let_it_be(:project) { create(:project, organization: current_organization) }
      let_it_be(:agent) { create(:cluster_agent, project: project, name: 'my-agent') }

      it 'registers a new environment' do
        visit deploy_environments_organization_path(current_organization)

        expect(page).to have_content(s_('ContinuousDeployment|Get started with environments'))

        click_button 'Register environment'
        fill_in 'environment-name', with: 'production-eu'

        select_from_listbox(agent.name, from: s_('ContinuousDeployment|Select an agent'))

        within_testid('register-environment-panel-footer') do
          click_button 'Register environment'
        end

        expect(page).to have_content('production-eu')
      end
    end
  end
end
