# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Analytics::DashboardsController, feature_category: :product_analytics do
  using RSpec::Parameterized::TableSyntax

  describe 'GET /:namespace/:project/-/analytics/dashboards' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:user) { project.first_owner }

    before do
      login_as(user)
    end

    shared_examples 'returns not found' do
      it 'returns 404 response' do
        send_dashboards_request

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'does not increment counter' do
        expect(Gitlab::InternalEvents).not_to receive(:track_event)

        send_dashboards_request
      end
    end

    shared_examples 'returns success' do
      it 'returns 200 response' do
        send_dashboards_request

        expect(response).to have_gitlab_http_status(:ok)
      end

      it_behaves_like 'internal event tracking' do
        let(:event) { 'analytics_dashboard_viewed' }

        subject(:track_event) { send_dashboards_request }
      end
    end

    describe 'for personal namespace projects' do
      it_behaves_like 'returns not found'
    end

    describe 'for group namespace projects' do
      let_it_be(:group) { create(:group) }
      let_it_be_with_reload(:project) { create(:project, :repository, group: group) }

      context 'without the licensed feature' do
        before do
          stub_licensed_features(project_level_analytics_dashboard: false)
        end

        it_behaves_like 'returns not found'
      end

      context 'with the licensed feature' do
        where(:access_level, :example_to_run) do
          nil         | 'returns not found'
          :guest      | 'returns not found'
          :reporter   | 'returns success'
          :developer  | 'returns success'
          :maintainer | 'returns success'
        end

        with_them do
          let(:user) { create(:user, :with_namespace) }

          before do
            stub_licensed_features(project_level_analytics_dashboard: true)
            project.add_member(user, access_level)
          end

          it_behaves_like params[:example_to_run]
        end

        it 'does not count views for the dashboard listing' do
          expect(Gitlab::InternalEvents).not_to receive(:track_event)

          get project_analytics_dashboards_path(project)
        end
      end
    end

    describe 'GET duo_and_sdlc_trends' do
      let_it_be(:group) { create(:group) }
      let_it_be_with_reload(:project) { create(:project, :repository, group: group) }
      let_it_be(:user) { create(:user, :with_namespace) }

      before_all do
        project.add_reporter(user)
      end

      before do
        stub_licensed_features(project_level_analytics_dashboard: true)
      end

      it 'redirects to Explore scoped to the project' do
        send_duo_and_sdlc_trends_request

        expect(response).to redirect_to(
          explore_analytics_dashboards_path(vueroute: 'duo_and_sdlc_trends', scope: project.full_path)
        )
      end

      it 'does not count a legacy dashboard view' do
        expect(Gitlab::InternalEvents).not_to receive(:track_event).with('analytics_dashboard_viewed', any_args)

        send_duo_and_sdlc_trends_request
      end

      context 'when the user cannot reach Explore analytics dashboards' do
        before do
          stub_feature_flags(explore_analytics_dashboards: false)
        end

        it 'renders the legacy dashboard' do
          send_duo_and_sdlc_trends_request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the user is not authorized to view the project dashboards' do
        let_it_be(:other_user) { create(:user, :with_namespace) }

        before do
          login_as(other_user)
        end

        it 'denies access instead of redirecting' do
          send_duo_and_sdlc_trends_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      def send_duo_and_sdlc_trends_request
        get project_analytics_dashboards_path(project, vueroute: 'duo_and_sdlc_trends')
      end
    end

    private

    def send_dashboards_request
      get project_analytics_dashboards_path(project, vueroute: 'dashboard_audience')
    end
  end
end
