# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Disable Merge Trains Setting', :js, feature_category: :merge_trains do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:merge_pipelines_label) { s_('ProjectSettings|Enable merged results pipelines') }
  let(:merge_trains_label) { s_('ProjectSettings|Enable merge trains') }

  before do
    stub_licensed_features(merge_pipelines: true, merge_trains: true)

    project.add_maintainer(user)
    sign_in(user)
  end

  shared_examples 'loads correct checkbox state' do
    it 'merge pipelines checkbox is always enabled' do
      expect(page).to have_field(merge_pipelines_label, disabled: false)
    end

    it 'merge trains checkbox is enabled only when merge_pipelines_enabled is true' do
      expect(page).to have_field(merge_trains_label, disabled: !project.merge_pipelines_enabled)
    end
  end

  context 'when visiting the project settings page' do
    using RSpec::Parameterized::TableSyntax

    where(:merge_pipelines_setting, :merge_trains_setting) do
      true  | true
      true  | false
      false | true
      false | false
    end

    with_them do
      before do
        project.update!(merge_pipelines_enabled: merge_pipelines_setting, merge_trains_enabled: merge_trains_setting)
        visit project_settings_merge_requests_path(project)
      end

      include_examples 'loads correct checkbox state'
    end
  end

  context 'when merge pipelines is enabled' do
    before do
      project.update!(merge_pipelines_enabled: true)
      visit project_settings_merge_requests_path(project)
    end

    include_examples 'loads correct checkbox state'

    it "checking merge trains checkbox doesn't affect merge pipelines checkbox" do
      check merge_trains_label

      expect(page).to have_field(merge_trains_label, checked: true)
      expect(page).to have_field(merge_pipelines_label, disabled: false, checked: true)
    end

    it 'unchecking merge pipelines checkbox disables merge trains checkbox' do
      uncheck merge_pipelines_label

      expect(page).to have_field(merge_pipelines_label, checked: false)
      expect(page).to have_field(merge_trains_label, disabled: true)
    end

    it 'unchecking merge pipelines checkbox unchecks merge trains checkbox if it was previously checked' do
      check merge_trains_label
      uncheck merge_pipelines_label

      expect(page).to have_field(merge_pipelines_label, checked: false)
      expect(page).to have_field(merge_trains_label, disabled: true, checked: false)
    end
  end

  context 'when merge pipelines is disabled' do
    before do
      project.update!(merge_pipelines_enabled: false)
      visit project_settings_merge_requests_path(project)
    end

    include_examples 'loads correct checkbox state'

    it 'checking merge pipelines checkbox enables merge trains checkbox' do
      check merge_pipelines_label

      expect(page).to have_field(merge_pipelines_label, checked: true)
      expect(page).to have_field(merge_trains_label, disabled: false)
    end

    it 'checking merge pipelines checkbox should leave merge trains checkbox unchecked' do
      check merge_pipelines_label

      expect(page).to have_field(merge_pipelines_label, checked: true)
      expect(page).to have_field(merge_trains_label, checked: false)
    end
  end

  context 'when both merge pipelines and merge trains are enabled' do
    before do
      project.update!(merge_pipelines_enabled: true, merge_trains_enabled: true)
      visit project_settings_merge_requests_path(project)
    end

    include_examples 'loads correct checkbox state'

    it 'unchecking merge pipelines checkbox disables and unchecks merge trains checkbox' do
      uncheck merge_pipelines_label

      expect(page).to have_field(merge_pipelines_label, checked: false)
      expect(page).to have_field(merge_trains_label, disabled: true, checked: false)
    end

    it "unchecking merge trains checkbox doesn't affect merge pipelines checkbox" do
      uncheck merge_trains_label

      expect(page).to have_field(merge_trains_label, checked: false)
      expect(page).to have_field(merge_pipelines_label, disabled: false, checked: true)
    end
  end
end
