# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Explore > Analytics dashboards > System dashboards', :js, :with_current_organization,
  feature_category: :custom_dashboards_foundation do
  include ListboxHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }

  before do
    stub_licensed_features(product_analytics: true)
    # The Duo dashboard declares `constraints.data: [clickhouse]`, so it is only
    # offered when ClickHouse is enabled. Contexts below override this.
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    sign_in(user)
  end

  def select_group(group)
    find_button(s_('AnalyticsDashboards|Select a group or project')).click
    select_listbox_item(group.name)
  end

  describe 'GitLab Duo and SDLC trends' do
    # `let`, not `let_it_be`, for the dashboards in this file: no records are created, and
    # `let_it_be` freezes its subject, which here is an object the loader memoizes for the
    # lifetime of the RSpec process.
    let(:duo_dashboard) do
      Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('duo_and_sdlc_trends')
    end

    let(:dashboard_title) { duo_dashboard.config['title'] }

    # Titles carrying `%{namespaceName}`-style placeholders are interpolated at render
    # time, so only the literal ones can be matched against the page.
    let(:panel_titles) { duo_dashboard.config['panels'].pluck('title').grep_v(/%\{/) }

    before do
      visit explore_analytics_dashboards_path
      click_link duo_dashboard.name
    end

    it 'routes to the dashboard by slug' do
      expect(page).to have_current_path(
        "#{explore_analytics_dashboards_path}/#{duo_dashboard.slug}",
        ignore_query: true
      )
    end

    it 'prompts for a namespace before rendering any panel', :aggregate_failures do
      expect(page).to have_content s_('AnalyticsDashboards|Select a group or project')
      expect(page).to have_no_content panel_titles.first
    end

    context 'when a group is selected' do
      before do
        select_group(group)
      end

      it_behaves_like 'a rendered analytics dashboard'

      # One example rather than several: the before hook mounts every panel,
      # which dominates the runtime, and each example would repeat it.
      it 'replaces the empty state with the dashboard panels', :aggregate_failures do
        expect(page).to have_no_testid('no-namespace-empty-state')
        expect(page).to have_content dashboard_title
        expect(page).to have_content s_('Analytics|No results match your query or filter.')
      end
    end

    context 'when ClickHouse is not enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)

        visit explore_analytics_dashboards_path
      end

      it 'does not offer the dashboard' do
        expect(page).to have_no_link duo_dashboard.name
      end
    end

    context 'when ClickHouse is enabled for analytics' do
      before do
        visit explore_analytics_dashboards_path
      end

      it 'offers the dashboard' do
        expect(page).to have_link duo_dashboard.name
      end
    end
  end

  describe 'DAP Impact' do
    let(:dap_dashboard) do
      Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('dap_impact')
    end

    let(:view_titles) { dap_dashboard.config['views'].pluck('title') }
    let(:overview_panel_title) { dap_dashboard.config['views'].first['panels'].first['title'] }
    let(:adoption_view) { dap_dashboard.config['views'].second }
    let(:adoption_sections) { adoption_view['panels'].select { |panel| panel.key?('section') }.pluck('section') }

    before do
      visit explore_analytics_dashboards_path
      click_link dap_dashboard.name
    end

    it 'routes to the dashboard by slug' do
      expect(page).to have_current_path(
        "#{explore_analytics_dashboards_path}/#{dap_dashboard.slug}",
        ignore_query: true
      )
    end

    it 'renders a tab per view, in order' do
      within_testid('dashboard-views') do
        expect(page.all('a', minimum: view_titles.size).map(&:text)).to eq(view_titles)
      end
    end

    it 'prompts for a namespace before rendering any panel', :aggregate_failures do
      expect(page).to have_content s_('AnalyticsDashboards|Select a group or project')
      expect(page).to have_no_content overview_panel_title
    end

    # The 30 here is hardcoded, not read from the config, so a changed YAML default breaks this
    # test and forces a deliberate decision, rather than the test silently following the config.
    it 'renders the date range filter, defaulting to the last 30 days', :aggregate_failures do
      expect(page).to have_content s_('AnalyticsDashboards|Date range')
      expect(find_by_testid('dashboard-filters-date-range'))
        .to have_text format(_('Last %{days} days'), days: 30)
    end

    # The URL round trip is only observable here: jest asserts the argument handed to
    # updateHistory, and jsdom cannot reload the page.
    it 'keeps the selected date range in the URL and restores it on reload', :aggregate_failures do
      within_testid('dashboard-filters-date-range') do
        toggle_listbox
        select_listbox_item(format(_('Last %{days} days'), days: 7), exact_text: true)
      end

      expect(page).to have_current_path(/date_range=7d/)

      page.refresh

      expect(find_by_testid('dashboard-filters-date-range'))
        .to have_text format(_('Last %{days} days'), days: 7)
    end

    context 'when a group is selected' do
      before do
        select_group(group)
      end

      # Only the panel chrome is asserted. The panel queries ClickHouse through a licensed
      # feature, so whether it settles on a value, an empty state or an error is environmental.
      it 'renders the Overview panel', :aggregate_failures do
        expect(page).to have_no_testid('no-namespace-empty-state')
        expect(page).to have_content overview_panel_title
      end

      it 'shows only the selected view, with its section headings, when switching tabs',
        :aggregate_failures do
        within_testid('dashboard-views') { click_link view_titles.second }

        expect(page).to have_no_content overview_panel_title
        expect(page).to have_current_path(/view=1/)

        adoption_sections.each do |section|
          within_testid("section-#{section['title'].downcase.tr(' ', '-')}") do
            expect(page).to have_text(section['title'])
            expect(page).to have_text(section['description'])
          end
        end
      end

      # `:click_house` routes this to the clickhouse25 system job. The plain rspec-ee system job
      # runs with `--tag ~click_house` and has no ClickHouse, so every GLQL panel errors there.
      { 'Adoption' => 1, 'Work' => 2 }.each do |view_title, view_index|
        context "and the #{view_title} tab is selected", :click_house do
          let(:view) { dap_dashboard.config['views'][view_index] }
          # Sections carry no visualization, so only the real panels take part in the GLQL checks.
          let(:view_panels) { view['panels'].reject { |panel| panel.key?('section') } }
          let(:view_panel_titles) { view_panels.pluck('title') }

          # The data source panels carry no GLQL query, so they sit out the GLQL checks.
          let(:glql_queries) do
            view_panels.filter_map { |panel| panel.dig('visualization', 'data', 'query', 'glql') }
          end

          let(:glql_configs) { glql_queries.map { |glql| YAML.safe_load(glql) } }

          # Breakdown tiles blank their description on purpose, so only the ones with copy are asserted.
          let(:stat_descriptions) do
            glql_configs
              .select { |config| config['display'] == 'stat' }
              .filter_map { |config| config.dig('displayConfig', 'description').presence }
          end

          # A dimensioned GLQL panel and a data source panel both render the same empty state when
          # their query matches nothing, so both count towards the expected occurrences.
          let(:empty_state_panel_count) do
            glql_configs.count { |config| config.key?('dimensions') } +
              (view_panels.size - glql_queries.size)
          end

          # The GLQL executor runs one query at a time, and a trend stat queues its comparison query
          # behind every main query already waiting, so the last trend stat is the last panel to settle.
          # Only stats carry a description, so a trend table cannot stand in for one.
          let(:last_trend_stat_description) do
            view_panels
              .select { |panel| panel.dig('visualization', 'options', 'showTrends') }
              .filter_map { |panel| panel.dig('visualization', 'data', 'query', 'glql') }
              .map { |glql| YAML.safe_load(glql) }
              .reverse
              .find { |config| config['display'] == 'stat' }
              .dig('displayConfig', 'description')
          end

          before do
            # The panel queries need `read_pro_ai_analytics` and `read_cycle_analytics`, which the group
            # policy prevents without these.
            stub_licensed_features(product_analytics: true, ai_analytics: true, cycle_analytics_for_groups: true)

            clickhouse_fixture(:siphon_internal_events,
              [{ postgresql_schema: 'public', postgresql_table: 'merge_requests' }])

            within_testid('dashboard-views') { click_link view['title'] }
          end

          # Settled state first, absence second: have_no_content returns immediately when the text is
          # absent, so checked too early it passes while a panel's query is still compiling (async, in
          # WASM) or its GraphQL request is still in flight, and the error text has not appeared yet.
          it 'renders every panel without a GLQL error', :aggregate_failures do
            view_panel_titles.each { |title| expect(page).to have_content(title) }

            # The Work view drains 31 queries one at a time, which outlasts the default wait. One long
            # wait on the last panel to settle leaves the page settled for every check that follows.
            expect(page).to have_content(last_trend_stat_description, wait: 90)
            stat_descriptions.each { |description| expect(page).to have_content(description) }
            expect(page).to have_content(
              s_('Analytics|No results match your query or filter.'), count: empty_state_panel_count
            )
            expect(page).to have_no_content(s_('Analytics|Something went wrong.'))
          end
        end
      end
    end
  end
end
