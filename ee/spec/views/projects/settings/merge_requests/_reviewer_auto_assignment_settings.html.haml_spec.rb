# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/settings/merge_requests/_reviewer_auto_assignment_settings',
  feature_category: :code_review_workflow do
  let_it_be(:project) { build_stubbed(:project) }

  before do
    assign(:project, project)
    stub_licensed_features(code_owners: true)
  end

  it 'renders the settings title' do
    render

    expect(rendered).to have_content 'Automatic reviewer assignment'
  end

  it 'renders the settings description' do
    render

    expect(rendered).to have_content 'Automatically assign reviewers when a merge request is ready.'
  end

  it 'renders the checkbox' do
    render

    expect(rendered).to have_css('input[id=project_project_setting_attributes_reviewer_assignment_strategy]')
  end

  it 'does not offer a strategy choice', :aggregate_failures do
    render

    expect(rendered).not_to have_content 'Reviewer assignment strategy'
    expect(rendered).not_to have_field(
      'project[project_setting_attributes][reviewer_assignment_strategy]',
      with: 'dap_powered', visible: :all
    )
  end

  context 'when reviewer_assignment_strategy is code_owners' do
    before do
      allow(project).to receive(:project_setting).and_return(
        build(:project_setting, project: project, reviewer_assignment_strategy: :code_owners)
      )
    end

    it 'renders the checkbox as checked' do
      render

      expect(rendered).to have_checked_field(
        'project[project_setting_attributes][reviewer_assignment_strategy]',
        visible: :all
      )
    end
  end

  context 'when reviewer_assignment_strategy is still dap_powered' do
    before do
      allow(project).to receive(:project_setting).and_return(
        build(:project_setting, project: project, reviewer_assignment_strategy: :dap_powered)
      )
    end

    it 'renders the checkbox as unchecked' do
      render

      expect(rendered).not_to have_checked_field(
        'project[project_setting_attributes][reviewer_assignment_strategy]',
        visible: :all
      )
    end
  end
end
