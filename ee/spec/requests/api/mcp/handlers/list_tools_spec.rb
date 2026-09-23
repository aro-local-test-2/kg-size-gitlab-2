# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat -- JSON-RPC has single path for method invocation
RSpec.describe API::Mcp, 'List tools request', feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true, duo_features_enabled: true)
    stub_ee_application_setting(elasticsearch_search: true)
    allow(::Search::Zoekt).to receive(:search_enabled?).and_return(true)

    manager = ObjectSpace.each_object(Mcp::Tools::Manager).first
    manager.instance_variable_set(:@mcp_routes, nil)
    manager.instance_variable_set(:@tools, nil)
    manager.instance_variable_set(:@api_tools, nil)
    manager.instance_variable_set(:@aggregated_api_tools, nil)
  end

  describe 'POST /mcp with tools/list method' do
    let(:params) do
      {
        jsonrpc: '2.0',
        method: 'tools/list',
        id: '1'
      }
    end

    def post_list_tools
      post api('/mcp', user, oauth_access_token: access_token), params: params
    end

    it 'returns success' do
      post_list_tools

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['jsonrpc']).to eq(params[:jsonrpc])
      expect(json_response['id']).to eq(params[:id])
      expect(json_response.keys).to include('result')
    end

    it 'returns tools' do
      post_list_tools

      expect(json_response['result']['tools']).to be_present
    end

    it 'registers and surfaces every MCP tool defined in the codebase', :eager_load, :aggregate_failures do
      defined_tools = Mcp::Tools::Base::BaseService.descendants
        .reject { |klass| klass.superclass == Mcp::Tools::Base::BaseService }

      expect(defined_tools).not_to be_empty, 'No MCP tool services were discovered'

      surfaced_tools = Mcp::Tools::Manager.new.list_tools.values.map(&:class)

      unregistered = defined_tools - surfaced_tools

      expect(unregistered).to be_empty,
        "Tool services defined but not registered in Mcp::Tools::Manager: #{unregistered.map(&:name).join(', ')}"
    end

    it 'locks each tool to its publicly-contracted annotations', :aggregate_failures do
      post api('/mcp', user, oauth_access_token: access_token),
        params: params,
        headers: { 'X-Gitlab-Enabled-Mcp-Server-Toolsets' => 'all' }

      expected_annotations = {
        # write, non-destructive
        'add_branch' => { 'readOnlyHint' => false, 'destructiveHint' => false, 'toolset' => 'repository' },
        'save_merge_request' => { 'readOnlyHint' => false, 'destructiveHint' => false,
                                  'toolset' => 'merge_requests' },
        'fork_repository' => { 'readOnlyHint' => false, 'destructiveHint' => false, 'toolset' => 'repository' },
        'link_work_items' => { 'readOnlyHint' => false, 'destructiveHint' => false, 'toolset' => 'work_items' },
        'save_merge_request_review' => { 'readOnlyHint' => false, 'destructiveHint' => false,
                                         'toolset' => 'merge_requests' },
        'save_note' => { 'readOnlyHint' => false, 'destructiveHint' => false, 'toolset' => 'core' },
        'save_work_item' => { 'readOnlyHint' => false, 'destructiveHint' => false, 'toolset' => 'work_items' },
        'send_duo_session_input' => { 'readOnlyHint' => false, 'destructiveHint' => false,
                                      'toolset' => 'duo_agent_platform' },
        'start_duo_session' => { 'readOnlyHint' => false, 'destructiveHint' => true,
                                 'toolset' => 'duo_agent_platform' },
        'attach_scan_profile' => { 'destructiveHint' => false, 'readOnlyHint' => false,
                                   'toolset' => 'code_security' },
        'save_vulnerability' => { 'readOnlyHint' => false, 'destructiveHint' => false,
                                  'toolset' => 'code_security' },
        # write, destructive
        'accept_merge_request' => { 'readOnlyHint' => false, 'destructiveHint' => true,
                                    'toolset' => 'merge_requests' },
        'add_commit' => { 'readOnlyHint' => false, 'destructiveHint' => true, 'toolset' => 'repository' },
        'manage_pipeline' => { 'readOnlyHint' => false, 'destructiveHint' => true, 'toolset' => 'ci' },
        'save_pipeline' => { 'readOnlyHint' => false, 'destructiveHint' => true, 'toolset' => 'ci' },
        # read-only
        'get_artifact_file' => { 'readOnlyHint' => true, 'toolset' => 'ci' },
        'get_commit' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'get_duo_session' => { 'readOnlyHint' => true, 'toolset' => 'duo_agent_platform' },
        'get_job' => { 'readOnlyHint' => true, 'toolset' => 'ci' },
        'get_mcp_server_version' => { 'readOnlyHint' => true, 'toolset' => 'meta' },
        'get_merge_request' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'get_merge_request_commits' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'get_merge_request_conflicts' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'get_merge_request_diffs' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'get_merge_request_notes' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'get_merge_request_pipelines' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'get_pipeline' => { 'readOnlyHint' => true, 'toolset' => 'ci' },
        'get_pipeline_jobs' => { 'readOnlyHint' => true, 'toolset' => 'ci' },
        'get_project' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'get_repository_file' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'get_saved_view_work_items' => { 'readOnlyHint' => true, 'toolset' => 'work_items' },
        'get_user' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'get_vulnerability' => { 'readOnlyHint' => true, 'toolset' => 'code_security' },
        'get_work_item' => { 'readOnlyHint' => true, 'toolset' => 'work_items' },
        'get_work_item_types' => { 'readOnlyHint' => true, 'toolset' => 'work_items' },
        'list_branches' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'list_commits' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'list_duo_sessions' => { 'readOnlyHint' => true, 'toolset' => 'duo_agent_platform' },
        'list_groups' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'list_merge_requests' => { 'readOnlyHint' => true, 'toolset' => 'merge_requests' },
        'list_project_members' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'list_pipelines' => { 'readOnlyHint' => true, 'toolset' => 'ci' },
        'list_projects' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'list_releases' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'list_repository_tree' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'list_tags' => { 'readOnlyHint' => true, 'toolset' => 'repository' },
        'list_vulnerabilities' => { 'readOnlyHint' => true, 'toolset' => 'code_security' },
        'list_work_items' => { 'readOnlyHint' => true, 'toolset' => 'work_items' },
        'search' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'search_labels' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'semantic_search' => { 'readOnlyHint' => true, 'toolset' => 'core' },
        'list_wiki_pages' => { 'readOnlyHint' => true, 'toolset' => 'wikis' }
      }

      actual_annotations = json_response['result']['tools'].to_h { |tool| [tool['name'], tool['annotations']] }

      expect(actual_annotations).to eq(expected_annotations)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
