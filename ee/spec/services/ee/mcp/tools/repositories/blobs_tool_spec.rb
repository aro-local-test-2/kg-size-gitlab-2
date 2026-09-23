# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Repositories::BlobsTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :repository, developers: user) }

  let(:paths) { ['README.md'] }
  let(:params) { { project_id: project.full_path, paths: paths, ref: project.default_branch } }
  let(:tool) { described_class.new(current_user: user, params: params) }

  def set_exclusion_rules(rules)
    project.project_setting.update!(duo_context_exclusion_settings: { 'exclusion_rules' => rules })
  end

  context 'when the project has no exclusion rules' do
    it 'reads the blob', :aggregate_failures do
      result = tool.execute

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent].dig('repository', 'blobs', 'nodes', 0)).to include('path' => 'README.md')
    end
  end

  context 'when a requested path matches an exclusion rule' do
    before do
      set_exclusion_rules(['*.md'])
    end

    it 'returns an error without reading the blob', :aggregate_failures do
      expect(tool).not_to receive(:build_variables)

      result = tool.execute

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include('README.md', 'excluded from AI context')
    end
  end

  context 'when a negation rule re-includes the path' do
    before do
      set_exclusion_rules(['*.md', '!README.md'])
    end

    it 'reads the blob' do
      expect(tool.execute[:isError]).to be(false)
    end
  end

  context 'when an excluded path is requested in a traversal form' do
    let(:paths) { ['docs/../README.md'] }

    before do
      set_exclusion_rules(['*.md'])
    end

    # Ai::FileExclusionService cannot normalize this path and reports it as not excluded,
    # so without the traversal gate the exclusion rule would not be applied.
    it 'returns an error without reading the blob', :aggregate_failures do
      expect(tool).not_to receive(:build_variables)

      result = tool.execute

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include('path traversal sequence')
    end
  end

  context 'when only one of several paths is excluded' do
    let(:paths) { %w[README.md files/ruby/popen.rb] }

    before do
      set_exclusion_rules(['*.md'])
    end

    it 'reports only the excluded path', :aggregate_failures do
      result = tool.execute

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include('README.md')
      expect(result[:content].first[:text]).not_to include('popen.rb')
    end
  end
end
