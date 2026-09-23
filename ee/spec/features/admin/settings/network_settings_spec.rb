# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin updates EE network settings', :request_store, :enable_admin_mode,
  feature_category: :audit_events do
  include StubENV
  include Features::SettingsHelpers

  let_it_be(:admin) { create(:admin) }

  before do
    stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
    stub_licensed_features(admin_audit_log: true, audit_events: true)
    sign_in(admin)
    visit network_admin_application_settings_path
  end

  it 'changes audit events API rate limits settings' do
    within_testid('audit-events-api-limits-settings') do
      fill_field_with_new_value(
        format(_('Maximum requests to the %{api_name} API per minute per user'),
          api_name: 'GET /audit_events[/:id]'), '450')

      expect_save_settings

      expect_field_value(
        format(_('Maximum requests to the %{api_name} API per minute per user'),
          api_name: 'GET /audit_events[/:id]'), '450')
    end
  end

  it 'changes project audit events API rate limits settings' do
    within_testid('audit-events-api-limits-settings') do
      fill_field_with_new_value(
        format(_('Maximum requests to the %{api_name} API per minute per user per project'),
          api_name: 'GET /projects/:id/audit_events[/:audit_event_id]'), '450')

      expect_save_settings

      expect_field_value(
        format(_('Maximum requests to the %{api_name} API per minute per user per project'),
          api_name: 'GET /projects/:id/audit_events[/:audit_event_id]'), '450')
    end
  end

  it 'changes group audit events API rate limits settings' do
    within_testid('audit-events-api-limits-settings') do
      fill_field_with_new_value(
        format(_('Maximum requests to the %{api_name} API per minute per user per group'),
          api_name: 'GET /groups/:id/audit_events[/:audit_event_id]'), '450')

      expect_save_settings

      expect_field_value(
        format(_('Maximum requests to the %{api_name} API per minute per user per group'),
          api_name: 'GET /groups/:id/audit_events[/:audit_event_id]'), '450')
    end
  end
end
