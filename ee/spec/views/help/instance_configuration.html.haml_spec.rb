# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'help/instance_configuration', feature_category: :configuration do
  describe 'Rate Limits (EE)' do
    let(:instance_configuration) { build(:instance_configuration) }
    let(:settings) { instance_configuration.settings }
    let(:rate_limits) { settings[:rate_limits] }

    before do
      assign(:instance_configuration, instance_configuration)
    end

    context 'when incident_management_notification rate limit is present' do
      before do
        Gitlab::CurrentSettings.current_application_settings.update!(
          throttle_incident_management_notification_enabled: true,
          throttle_incident_management_notification_per_period: 3601,
          throttle_incident_management_notification_period_in_seconds: 3600
        )
      end

      context 'when signed in' do
        let_it_be(:user) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- Persisted user needed for sign_in

        before do
          sign_in(user)
        end

        it 'displays incident management inbound alert rate limit' do
          render
          expect(rendered).to include(
            "<td>Incident management inbound alert requests</td>\n<td>3601</td>\n<td>3600</td>"
          )
        end
      end

      context 'when signed out' do
        it 'does not display incident management inbound alert rate limits' do
          render
          expect(rendered).not_to have_content('Incident management inbound alert requests')
        end
      end
    end

    context 'when audit_events_api rate limit is present' do
      let_it_be(:user) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- Persisted user needed for sign_in

      let(:expected_rate_limit) { 150 }

      before do
        Gitlab::CurrentSettings.current_application_settings.update!(audit_events_api_limit: expected_rate_limit)
        sign_in(user)
      end

      context 'when admin_audit_log is licensed' do
        before do
          stub_licensed_features(admin_audit_log: true)
        end

        it 'displays the audit events API rate limit' do
          render
          expect(rendered).to have_content('Audit events API rate limits')
          expect(rendered).to have_content("GET /audit_events[/:id] #{expected_rate_limit}")
        end
      end

      context 'when admin_audit_log is not licensed' do
        before do
          stub_licensed_features(admin_audit_log: false, audit_events: false)
        end

        it 'does not display the audit events API rate limits section' do
          render
          expect(rendered).not_to have_content('Audit events API rate limits')
        end
      end
    end

    context 'when project_audit_events_api rate limit is present' do
      let_it_be(:user) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- Persisted user needed for sign_in

      let(:expected_rate_limit) { 150 }

      before do
        Gitlab::CurrentSettings.current_application_settings
          .update!(project_audit_events_api_limit: expected_rate_limit)
        sign_in(user)
      end

      context 'when audit_events is licensed' do
        before do
          stub_licensed_features(audit_events: true)
        end

        it 'displays the project audit events API rate limit' do
          render
          expect(rendered).to have_content('Audit events API rate limits')
          expect(rendered).to have_content("GET /projects/:id/audit_events[/:audit_event_id] #{expected_rate_limit}")
        end
      end

      context 'when audit_events is not licensed' do
        before do
          stub_licensed_features(audit_events: false)
        end

        it 'does not display the audit events API rate limits section' do
          render
          expect(rendered).not_to have_content('Audit events API rate limits')
        end
      end
    end

    context 'when group_audit_events_api rate limit is present' do
      let_it_be(:user) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- Persisted user needed for sign_in

      let(:expected_rate_limit) { 150 }

      before do
        Gitlab::CurrentSettings.current_application_settings
          .update!(group_audit_events_api_limit: expected_rate_limit)
        sign_in(user)
      end

      context 'when audit_events is licensed' do
        before do
          stub_licensed_features(audit_events: true)
        end

        it 'displays the group audit events API rate limit' do
          render
          expect(rendered).to have_content('Audit events API rate limits')
          expect(rendered).to have_content("GET /groups/:id/audit_events[/:audit_event_id] #{expected_rate_limit}")
        end
      end

      context 'when audit_events is not licensed' do
        before do
          stub_licensed_features(audit_events: false)
        end

        it 'does not display the audit events API rate limits section' do
          render
          expect(rendered).not_to have_content('Audit events API rate limits')
        end
      end
    end
  end
end
