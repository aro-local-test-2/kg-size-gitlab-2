# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'analytics dashboard JSON schemas', feature_category: :custom_dashboards_foundation do
  let(:schema_dir) { Rails.root.join('ee/app/validators/json_schemas') }
  let(:legacy_schema_path) { Analytics::Dashboards::Dashboard::SCHEMA_PATH }
  let(:explore_schema_path) { Analytics::CustomDashboards::SystemDashboardsLoader::SCHEMA_PATH }

  def errors_for(schema_path, config)
    schemer = JSONSchemer.schema(Pathname.new(Rails.root.join(schema_path)))
    schemer.validate(config).map { |error| JSONSchemer::Errors.pretty(error) }
  end

  def referenced_schemas(filename)
    File.read(schema_dir.join(filename)).scan(/"\$ref":\s*"([a-z_]+\.json)#/).flatten.uniq
  end

  it 'gives the group and project dashboards a schema of their own' do
    expect(legacy_schema_path).to end_with('analytics_dashboard_legacy.json')
    expect(Analytics::Dashboards::Visualization::SCHEMA_PATH).to end_with('analytics_visualization_legacy.json')
    expect(explore_schema_path).to end_with('analytics_dashboard.json')
  end

  it 'accepts the same dashboard definition under both schemas' do
    config = Gitlab::Config::Loader::Yaml
      .new(File.read(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_1.yaml')))
      .load_raw!

    expect(errors_for(legacy_schema_path, config)).to be_empty
    expect(errors_for(explore_schema_path, config)).to be_empty
  end

  # The group and project dashboard renderer has no branch for a panel without a
  # visualization, so the frozen schema must keep rejecting one.
  it 'rejects a panel-level section under the group and project schema' do
    config = {
      'version' => '2',
      'title' => 'Dashboard with a section',
      'panels' => [
        {
          'section' => { 'title' => 'Adoption tiers' },
          'gridAttributes' => { 'xPos' => 0, 'yPos' => 0, 'height' => 1 }
        }
      ]
    }

    expect(errors_for(legacy_schema_path, config)).not_to be_empty
  end

  it 'resolves the inline visualization reference on both sides' do
    config = Gitlab::Config::Loader::Yaml
      .new(File.read(Rails.root.join('ee/spec/fixtures/analytics/dashboard_example_inline_vis.yaml')))
      .load_raw!

    expect(errors_for(legacy_schema_path, config)).to be_empty
    expect(errors_for(explore_schema_path, config)).to be_empty
  end

  # Derived from the directory, not a fixed list, so a new built-in dashboard cannot skip
  # validation by not being added here. The explore app has the equivalent guard in
  # system_dashboards_loader_spec; before the split the two apps shared one.
  describe 'shipped group and project dashboards' do
    let(:shipped_dashboards) do
      Dir.glob(Rails.root.join('ee/lib/gitlab/analytics/**/*.yaml'))
        .reject { |path| path.include?('/visualizations/') || path.include?('/system/') }
    end

    it 'validates every one against the frozen schema', :aggregate_failures do
      expect(shipped_dashboards).not_to be_empty

      shipped_dashboards.each do |path|
        config = Gitlab::Config::Loader::Yaml.new(File.read(path)).load_raw!

        errors = errors_for(legacy_schema_path, config)

        expect(errors).to be_empty, "#{path} does not validate: #{errors.join(', ')}"
      end
    end
  end

  describe 'cross-file references' do
    it 'keeps the group and project schemas pointing only at each other' do
      expect(referenced_schemas('analytics_dashboard_legacy.json'))
        .to contain_exactly('analytics_visualization_legacy.json')
      expect(referenced_schemas('analytics_visualization_legacy.json'))
        .to contain_exactly('analytics_dashboard_legacy.json')
    end

    it 'keeps the explore schemas pointing only at each other' do
      expect(referenced_schemas('analytics_dashboard.json'))
        .to contain_exactly('analytics_visualization.json')
      expect(referenced_schemas('analytics_visualization.json'))
        .to contain_exactly('analytics_dashboard.json')
    end
  end
end
