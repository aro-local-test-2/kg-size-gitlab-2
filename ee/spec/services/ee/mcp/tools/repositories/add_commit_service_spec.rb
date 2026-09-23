# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Repositories::AddCommitService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :repository, developers: user) }

  let(:service) { described_class.new(name: 'add_commit') }
  let(:params) do
    {
      arguments: {
        project_id: project.full_path,
        branch: project.default_branch,
        commit_message: 'Update README',
        actions: [{ action: 'update', file_path: 'README.md', old_str: 'Sample repo', new_str: 'MCP' }]
      }
    }
  end

  before do
    service.set_cred(current_user: user)
  end

  context 'when the partial-edit target is excluded from AI context' do
    before do
      project.project_setting.update!(duo_context_exclusion_settings: { 'exclusion_rules' => ['*.md'] })
    end

    it 'does not commit and returns an error', :aggregate_failures do
      result = nil

      expect { result = service.execute(params: params) }.not_to change { project.repository.commit_count }
      expect(result[:isError]).to be(true)
      expect(result.dig(:content, 0, :text)).to include('excluded from AI context')
    end
  end
end
