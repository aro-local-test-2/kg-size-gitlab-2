# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Security::DashboardController, feature_category: :vulnerability_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }

  subject(:gitlab_request) { get security_dashboard_organization_path(organization) }

  before do
    stub_licensed_features(security_dashboard: true)
  end

  it 'declares the vulnerability_management feature category for #show' do
    expect(described_class.feature_category_for_action('show')).to eq(:vulnerability_management)
  end

  describe 'GET #show' do
    context 'when the user is not signed in' do
      it_behaves_like 'organization - redirects to sign in page'
    end

    context 'when the user is signed in' do
      before do
        sign_in(user)
      end

      context 'with no association to the organization' do
        it_behaves_like 'organization - not found response'
      end

      context 'as a non-owner member of the organization' do
        before_all do
          create(:organization_user, organization: organization, user: user)
        end

        it_behaves_like 'organization - not found response'
      end

      context 'as an owner of the organization' do
        before_all do
          create(:organization_user, :owner, organization: organization, user: user)
        end

        it_behaves_like 'organization - successful response'
        it_behaves_like 'organization - action disabled by org_pages release flag'

        it 'renders the element the dashboard mounts into' do
          gitlab_request

          expect(response.body).to have_css('#js-organization-security-dashboard')
        end

        it 'tracks the visit_upgraded_security_dashboard internal event', :clean_gitlab_redis_shared_state do
          expect { gitlab_request }
            .to trigger_internal_events('visit_upgraded_security_dashboard')
            .with(user: user, additional_properties: { organization_id: organization.id })
            .and increment_usage_metrics(
              'redis_hll_counters.count_distinct_organization_id_from_visit_upgraded_security_dashboard_monthly',
              'redis_hll_counters.count_distinct_organization_id_from_visit_upgraded_security_dashboard_weekly'
            )
        end

        context 'when the organization_security_dashboard feature flag is disabled' do
          before do
            stub_feature_flags(organization_security_dashboard: false)
          end

          it_behaves_like 'organization - not found response'

          it 'does not track the visit_upgraded_security_dashboard internal event' do
            expect { gitlab_request }.not_to trigger_internal_events('visit_upgraded_security_dashboard')
          end
        end

        context 'when the security_dashboard licensed feature is unavailable' do
          before do
            stub_licensed_features(security_dashboard: false)
          end

          it_behaves_like 'organization - not found response'
        end
      end

      context 'as an admin', :enable_admin_mode do
        let_it_be(:user) { create(:admin) }

        it_behaves_like 'organization - successful response'
      end
    end
  end
end
