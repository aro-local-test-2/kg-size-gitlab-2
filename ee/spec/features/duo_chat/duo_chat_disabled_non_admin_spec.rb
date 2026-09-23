# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Chat disabled non admin empty state', :js, feature_category: :duo_chat do
  include_context 'with duo features disabled and ai chat available for self-managed'

  let_it_be(:user) { create(:user, :with_namespace) }
  let_it_be(:group) { create(:group, developers: user) }

  before do
    sign_in(user)
    visit group_path(group)
  end

  it 'displays the non-admin empty state when the user opens the panel' do
    find_by_testid('duo-disabled-toggle').click

    within_testid('duo-disabled-non-admin-empty-state') do
      expect(page).to have_content('GitLab Duo Agent Platform is turned off')
      expect(page).to have_testid('duo-learn-more')
    end
  end
end
