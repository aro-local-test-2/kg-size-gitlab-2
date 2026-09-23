# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::FindingPresenter, feature_category: :vulnerability_management do
  describe '#location_link_with_raw_path' do
    subject(:location_link) { described_class.new(finding).location_link_with_raw_path }

    let(:project) { finding.project }
    let(:finding) do
      build_stubbed(:security_finding, :with_finding_data,
        location: { file: 'a.txt', start_line: 1 })
    end

    before do
      allow(finding).to receive(:sha).and_return('abc')
      stub_config_setting(relative_url_root: '/gitlab')
    end

    around do |example|
      previous_script_name = Rails.application.routes.default_url_options[:script_name]
      Rails.application.routes.default_url_options[:script_name] = '/gitlab'
      example.run
    ensure
      Rails.application.routes.default_url_options[:script_name] = previous_script_name
    end

    it 'includes the relative URL root once' do
      expected_path = Gitlab::Routing.url_helpers.project_raw_url(project, 'abc/a.txt')

      expect(location_link).to eq("#{expected_path}#L1")
    end
  end
end
