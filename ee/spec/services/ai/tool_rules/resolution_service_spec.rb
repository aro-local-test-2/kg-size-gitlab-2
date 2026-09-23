# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::ResolutionService, feature_category: :ai_agents do
  let_it_be_with_reload(:namespace) { create(:group) }

  let(:surface) { :web }
  let(:result) { service.execute }

  subject(:service) { described_class.new(namespace: namespace, surface: surface) }

  before do
    ::Ai::ToolRules::Registry.instance_variable_set(:@all_tool_names, nil)
    ::Ai::ToolRules::Registry.instance_variable_set(:@catalog_tool_names, nil)
    ::Ai::ToolRules::Registry.instance_variable_set(:@action_type_for, nil)

    # Specs enable flags by default, so this pins every example below to the shipped
    # default, which also makes the rest of the file a flag-off parity check.
    stub_feature_flags(duo_mcp_tool_governance: false)
  end

  context 'when the surface is ungoverned' do
    let(:surface) { ::Ai::ToolRules::GovernanceSurface::UNGOVERNED }

    # ToolRule#access_for falls through to local_access for an unrecognised surface, so
    # silently accepting the sentinel would resolve local rules while local governance
    # is off. See gitlab-org/gitlab#622602.
    it 'raises in development and test so the mistake is loud' do
      expect { result }.to raise_error(ArgumentError, /ungoverned/)
    end

    context 'in production, where dev exceptions are only tracked' do
      before do
        allow(::Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
      end

      it 'fails gracefully onto the callers existing error path', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:ungoverned_surface)
      end

      it 'does not look up any tool rules' do
        expect(::Ai::ToolRule).not_to receive(:for_namespace)

        expect(result.payload).to be_blank
      end

      it 'guards effective_rules too, which ToolRulesResolver calls without #execute' do
        expect(::Ai::ToolRule).not_to receive(:for_namespace)

        expect(service.effective_rules).to eq({})
      end

      it 'reports to error tracking, which is the only signal left in production' do
        result

        expect(::Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception)
          .with(an_instance_of(ArgumentError), namespace_id: namespace.id)
      end
    end
  end

  describe '#execute' do
    it 'returns a success response' do
      expect(result).to be_success
    end

    # Derived, not hand-listed, so a new LOCAL_ENVIRONMENTS entry is covered here too.
    it 'accepts every surface GovernanceSurface actually emits' do
      emitted = [:web, ::Ai::ToolRules::GovernanceSurface::BACKGROUND] +
        ::Ai::ToolRules::GovernanceSurface::LOCAL_ENVIRONMENTS.map(&:to_sym)

      emitted.each do |surface|
        expect { described_class.new(namespace: namespace, surface: surface).execute }.not_to raise_error
      end
    end

    it 'always includes START_FLOWS in both privilege lists' do
      expect(result.payload[:agent_privileges]).to include(
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
      )
      expect(result.payload[:pre_approved_agent_privileges]).to include(
        ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
      )
    end

    context 'when no explicit rules are configured' do
      it 'falls back to :ask for non-preapproved groups', :aggregate_failures do
        expect(result.payload[:pre_approved_tools]).not_to be_empty
        expect(result.payload[:pre_approved_agent_privileges]).not_to include(
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
        )
      end
    end

    context 'when no rules exist for the namespace' do
      it 'includes all privilege group constants in agent_privileges' do
        expect(result.payload[:agent_privileges]).to include(
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_MCP_TOOLS
        )
      end

      it 'only includes the read-only GitLab group in pre_approved_agent_privileges' do
        expect(result.payload[:pre_approved_agent_privileges]).to match_array([
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
        ])
      end

      it 'returns pre_approved_tools only for preapproved groups', :aggregate_failures do
        expect(result.payload[:pre_approved_tools]).not_to be_empty
        expect(result.payload[:pre_approved_tools]).to include('list_issues')
        expect(result.payload[:pre_approved_tools]).not_to include('create_work_item', 'read_file', 'run_command')
        expect(result.payload[:denied_tools]).to be_empty
      end
    end

    context 'when rules exist for the namespace' do
      context 'when a group has a deny rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :deny)
        end

        it 'includes the group constant in agent_privileges, keeping the category askable' do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'excludes the group from pre_approved_agent_privileges' do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'includes the tool in denied_tools' do
          expect(result.payload[:denied_tools]).to include('create_work_item')
        end
      end

      context 'when a group has an ask rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
        end

        it 'includes the group constant in agent_privileges' do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'excludes the group from pre_approved_agent_privileges' do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'does not include the tool in pre_approved_tools' do
          expect(result.payload[:pre_approved_tools]).not_to include('create_work_item')
        end

        it 'includes the tool in ask_tools' do
          expect(result.payload[:ask_tools]).to include('create_work_item')
        end
      end

      context 'when every tool in the default-allow group is set to ask' do
        let(:read_only_gitlab_tools) do
          ::Ai::ToolRules::Registry.all_tool_names.select do |name|
            ::Ai::ToolRules::Registry::PRIVILEGE_GROUP_FOR[name] == :read_only_gitlab
          end
        end

        before do
          read_only_gitlab_tools.each do |tool_name|
            create(:ai_tool_rule, namespace: namespace, tool_name: tool_name, web_access: :ask)
          end
        end

        it 'reports the asked tools rather than an empty resolution', :aggregate_failures do
          # The strictest configuration an admin can apply must not be
          # indistinguishable from "no governance configured" -- consumers infer
          # whether governance is active from these lists.
          expect(result.payload[:pre_approved_tools]).to be_empty
          expect(result.payload[:denied_tools]).to be_empty
          expect(result.payload[:ask_tools]).to match_array(
            ::Ai::ToolRules::Registry.to_mcp_tool_names(read_only_gitlab_tools)
          )
        end
      end

      context 'when one tool has an allow rule and the rest of the group is unconfigured' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow)
        end

        it 'includes the group constant in agent_privileges' do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'excludes the group from pre_approved_agent_privileges' do
          # Unconfigured tools keep the group's ask default, so one allow must not
          # pre-approve the whole group.
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'includes the MCP tool name in pre_approved_tools' do
          expect(result.payload[:pre_approved_tools]).to include('create_work_item')
        end

        it 'leaves the other payload lists unaffected by the group demotion', :aggregate_failures do
          expect(result.payload[:pre_approved_tools]).not_to include('update_issue', 'create_merge_request')
          expect(result.payload[:denied_tools]).to be_empty
          expect(result.payload[:ask_tools]).to be_empty
        end
      end

      context 'when every governed tool in a group has an allow rule' do
        before_all do
          ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: :read_write_gitlab).each do |tool_name|
            create(:ai_tool_rule, namespace: namespace, tool_name: tool_name, web_access: :allow)
          end
        end

        it 'includes the group constant in pre_approved_agent_privileges' do
          # Mapped names without a catalog entry can never carry a rule, so they must
          # not block pre-approval of an otherwise fully configured group.
          expect(result.payload[:pre_approved_agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end

      context 'when every governed tool except one has an allow rule' do
        before_all do
          ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: :read_write_gitlab).each do |tool_name|
            next if tool_name == 'update_issue'

            create(:ai_tool_rule, namespace: namespace, tool_name: tool_name, web_access: :allow)
          end
        end

        it 'excludes the group from pre_approved_agent_privileges' do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end

      context 'when every governed tool in a group has a deny rule' do
        before_all do
          ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: :read_write_gitlab).each do |tool_name|
            create(:ai_tool_rule, namespace: namespace, tool_name: tool_name, web_access: :deny)
          end
        end

        it 'excludes the group constant from agent_privileges' do
          # Only a full, deliberate denial of every governed tool excludes the
          # category; a partial denial resolves to ask so admins can still be
          # asked about the other tools in the group.
          expect(result.payload[:agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'excludes the group from pre_approved_agent_privileges' do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'includes every governed tool in denied_tools' do
          expect(result.payload[:denied_tools]).to include('create_work_item', 'update_issue')
        end
      end

      context 'when every governed tool except one has a deny rule' do
        before_all do
          ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: :read_write_gitlab).each do |tool_name|
            next if tool_name == 'update_issue'

            create(:ai_tool_rule, namespace: namespace, tool_name: tool_name, web_access: :deny)
          end
        end

        it 'keeps the group in agent_privileges because one tool is not denied' do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end

      context 'when every governed tool is configured with only deny and ask (no allow)' do
        before_all do
          tools = ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: :read_write_gitlab)
          tools.each_with_index do |tool_name, index|
            access = index.even? ? :deny : :ask
            create(:ai_tool_rule, namespace: namespace, tool_name: tool_name, web_access: access)
          end
        end

        it 'resolves to ask, not allow and not full deny', :aggregate_failures do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end

      context 'when a single-tool group has an allow rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'run_git_command', web_access: :allow)
        end

        it 'includes the group constant in pre_approved_agent_privileges' do
          expect(result.payload[:pre_approved_agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
          )
        end
      end

      context 'when a single-tool group has a deny rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'run_git_command', web_access: :deny)
        end

        it 'excludes the group constant from agent_privileges because the only tool is denied' do
          expect(result.payload[:agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
          )
        end

        it 'includes the tool in denied_tools' do
          expect(result.payload[:denied_tools]).to include('run_git_command')
        end
      end

      context 'when a single-tool group has a rule with no value for the queried surface' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'run_git_command',
            web_access: nil, local_access: :allow)
        end

        it 'treats the rule as unconfigured and excludes the group from pre-approval' do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
          )
        end
      end

      context 'when a default-allow group has a partial allow rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'list_issues', web_access: :allow)
        end

        it 'keeps the group pre-approved because unconfigured tools default to allow' do
          expect(result.payload[:pre_approved_agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB
          )
        end
      end

      context 'when a default-allow group has an ask rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'get_issue', web_access: :ask)
        end

        it 'excludes the group from pre_approved_agent_privileges' do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB
          )
        end
      end

      context 'when tools in a group have mixed permissions' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow)
          create(:ai_tool_rule, namespace: namespace, tool_name: 'update_issue', web_access: :deny)
        end

        it 'keeps the group in agent_privileges because the group is not fully denied' do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end

        it 'includes the allowed tool in pre_approved_tools' do
          expect(result.payload[:pre_approved_tools]).to include('create_work_item')
        end

        it 'includes the denied tool in denied_tools' do
          expect(result.payload[:denied_tools]).to include('update_issue')
        end
      end
    end

    context 'when read_only_files group has a rule' do
      context 'when a tool in the group is denied' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'read_file', web_access: :deny)
        end

        it 'includes READ_ONLY_FILES in agent_privileges and includes the tool in denied_tools',
          :aggregate_failures do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES
          )
          expect(result.payload[:denied_tools]).to include('read_file')
        end
      end
    end

    context 'when surface is local' do
      let(:surface) { :local }

      before do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue',
          web_access: :deny, local_access: :allow)
      end

      it 'uses local_access instead of web_access', :aggregate_failures do
        # local_access: :allow (not web_access: :deny) governs this surface, so
        # create_issue resolves to allow here; this spec is about surface
        # selection, not the deny-scoping safeguard.
        expect(result.payload[:agent_privileges]).to include(
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
        )
        expect(result.payload[:pre_approved_agent_privileges]).not_to include(
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
        )
        expect(result.payload[:pre_approved_tools]).to include('create_work_item')
      end
    end

    context 'when surface is ambient' do
      let(:surface) { :ambient }

      before do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'run_git_command', web_access: :allow)
      end

      it 'treats ambient as a web surface' do
        expect(result.payload[:pre_approved_agent_privileges]).to include(
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
        )
      end
    end

    context 'when project is provided' do
      let_it_be(:project) { create(:project, namespace: namespace) }

      subject(:service) { described_class.new(namespace: namespace, surface: surface, project: project) }

      context 'when project has no rules — inherits namespace rules' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
        end

        it 'uses the namespace rule', :aggregate_failures do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end

      context 'when project escalates namespace rule (ask → deny)' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
          create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', web_access: :deny)
        end

        it 'applies the more restrictive project rule to the tool without denying the whole group',
          :aggregate_failures do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
          expect(result.payload[:denied_tools]).to include('create_work_item')
        end
      end

      context 'when only a project rule exists with no namespace rule' do
        before do
          create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', web_access: :deny)
        end

        it 'applies the project rule' do
          expect(result.payload[:denied_tools]).to include('create_work_item')
        end
      end

      context 'when a project allow rule is the only rule in the group' do
        before do
          create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', web_access: :allow)
        end

        it 'excludes the group from pre-approval but keeps the tool in pre_approved_tools',
          :aggregate_failures do
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
          expect(result.payload[:pre_approved_tools]).to include('create_work_item')
        end
      end

      context 'when namespace rule has nil for the queried surface' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: nil, local_access: :deny)
          create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', web_access: :allow)
        end

        it 'allows project rule to set the unconfigured surface' do
          expect(result.payload[:pre_approved_tools]).to include('create_work_item')
        end
      end

      context 'when project rule has nil for the queried surface' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
          create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', web_access: nil,
            local_access: :deny)
        end

        it 'keeps the namespace rule for the unconfigured surface', :aggregate_failures do
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
          expect(result.payload[:pre_approved_agent_privileges]).not_to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end
    end

    context 'when surface is background' do
      let(:surface) { :background }

      context 'when no background rule is set' do
        it 'coerces the ask default to allow so un-ruled tools run (nil->allow rollout)', :aggregate_failures do
          # run_command defaults to :ask on web/local; on a background flow there is no
          # approver, so it must resolve to allow rather than land in neither list.
          expect(result.payload[:denied_tools]).to be_empty
          expect(result.payload[:agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS
          )
          expect(result.payload[:pre_approved_agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS
          )
        end
      end

      context 'when a web ask rule exists but the surface is background' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
        end

        it 'returns no ask_tools' do
          # `ask` is not a valid background permission (BACKGROUND_ACCESS_LEVELS
          # excludes it) -- a background flow has no human to approve.
          expect(result.payload[:ask_tools]).to be_empty
        end
      end

      context 'when a background_access deny rule is set' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', background_access: :deny)
        end

        # `create_issue` resolves to the MCP tool name `create_work_item` in the
        # returned allow/deny lists (matches the existing web-surface deny spec above).
        it 'includes the tool in denied_tools' do
          expect(result.payload[:denied_tools]).to include('create_work_item')
        end
      end

      context 'when a background_access allow rule is set' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', background_access: :allow)
        end

        it 'includes the tool in pre_approved_tools and not denied', :aggregate_failures do
          expect(result.payload[:pre_approved_tools]).to include('create_work_item')
          expect(result.payload[:denied_tools]).not_to include('create_work_item')
        end

        it 'keeps the group pre-approved even though the rest of the group is unconfigured' do
          # On the background surface the group default coerces to allow, so a
          # partial configuration must not demote the group there.
          expect(result.payload[:pre_approved_agent_privileges]).to include(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
          )
        end
      end

      context 'when a web/local-only rule exists with background_access unset' do
        before do
          # read_file has no distinct MCP alias in its group, so this genuinely
          # exercises the per-tool background fallback (a duplicate-named tool would
          # be pre-approved via its unruled sibling and mask the behaviour).
          create(:ai_tool_rule, namespace: namespace, tool_name: 'read_file', web_access: :deny)
        end

        it 'treats the unset background permission as allow, matching the displayed default', :aggregate_failures do
          # A rule with background_access nil must behave like no background rule on the background
          # surface (nil->allow), so display (resolver) and enforcement agree.
          expect(result.payload[:pre_approved_tools]).to include('read_file')
          expect(result.payload[:denied_tools]).not_to include('read_file')
        end
      end
    end

    context 'when surface is web and a background-only rule exists' do
      let(:surface) { :web }

      before do
        # A background-only rule leaves web_access nil; on web it must fall back to the
        # group default, so a background rule never demotes a default-allow tool on web.
        create(:ai_tool_rule, namespace: namespace, tool_name: 'list_issues', web_access: nil, background_access: :deny)
      end

      it 'keeps the default-allow tool pre-approved on web, matching the displayed default' do
        expect(result.payload[:pre_approved_tools]).to include('list_issues')
      end
    end

    context 'with GitLab MCP server tool governance' do
      let(:mcp_tools) do
        instance_double(
          Ai::ToolRules::GovernedMcpTools,
          empty?: false,
          rulable_names: %w[search manage_pipeline]
        )
      end

      let(:baseline_payload) { described_class.new(namespace: namespace, surface: surface).execute.payload }

      def stub_governed_mcp_tools(catalog)
        allow(Ai::ToolRules::GovernedMcpTools).to receive(:for).with(namespace).and_return(catalog)
      end

      before do
        allow(mcp_tools).to receive(:spellings_for).and_return([])
        allow(mcp_tools).to receive(:spellings_for).with('search').and_return(['gitlab_search'])
        allow(mcp_tools).to receive(:spellings_for).with('manage_pipeline')
          .and_return(['gitlab_manage_pipeline'])
        allow(mcp_tools).to receive(:spellings_for).with('get_work_item_notes')
          .and_return(['gitlab_get_workitem_notes'])
      end

      context 'with the real catalog' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'get_work_item_notes', web_access: :deny)
        end

        it 'denies only the catalog name when the flag is disabled' do
          expect(result.payload[:denied_tools]).to contain_exactly('get_work_item_notes')
        end

        it 'also denies the MCP spelling when the flag is enabled' do
          stub_feature_flags(duo_mcp_tool_governance: namespace)

          expect(result.payload[:denied_tools])
            .to contain_exactly('get_work_item_notes', 'gitlab_get_workitem_notes')
        end
      end

      context 'when the catalog is empty' do
        before do
          stub_governed_mcp_tools(Ai::ToolRules::GovernedMcpTools.none)
        end

        it 'emits exactly what it emits with no MCP catalog at all' do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'get_work_item_notes', web_access: :deny)

          expect(result.payload[:pre_approved_tools]).to match_array(baseline_payload[:pre_approved_tools])
          expect(result.payload[:denied_tools]).to match_array(baseline_payload[:denied_tools])
          expect(result.payload[:ask_tools]).to match_array(baseline_payload[:ask_tools])
        end
      end

      context 'when the catalog is populated' do
        before do
          stub_governed_mcp_tools(mcp_tools)
        end

        context 'without any rule' do
          it 'adds no MCP name of its own, leaving the annotation-derived list in charge' do
            expect(result.payload[:denied_tools]).to be_empty
            expect(result.payload[:ask_tools]).to be_empty
            expect(result.payload[:pre_approved_tools]).not_to include('gitlab_manage_pipeline')
          end

          it 'keeps every catalog name it emits without a catalog' do
            expect(result.payload[:pre_approved_tools]).to include(*baseline_payload[:pre_approved_tools])
          end
        end

        context 'with a deny rule on a capability whose MCP spelling differs' do
          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'get_work_item_notes', web_access: :deny)
          end

          it 'denies both spellings, so the rule reaches the MCP transport too' do
            expect(result.payload[:denied_tools])
              .to include('get_work_item_notes', 'gitlab_get_workitem_notes')
          end

          it 'leaves the read privilege and the other read tools alone' do
            expect(result.payload[:agent_privileges])
              .to include(::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB)
            expect(result.payload[:denied_tools]).not_to include('get_issue')
          end
        end

        context 'with a deny rule on an MCP-only tool' do
          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'search', web_access: :deny)
          end

          it 'denies the prefixed spelling the Duo Workflow Service uses' do
            expect(result.payload[:denied_tools]).to include('gitlab_search')
          end

          it 'does not withdraw the read privilege group' do
            expect(result.payload[:pre_approved_agent_privileges])
              .to include(::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB)
          end
        end

        context 'with an ask rule on an MCP-only tool' do
          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'search', web_access: :ask)
          end

          it 'asks for the prefixed spelling and does not pre-approve it' do
            expect(result.payload[:ask_tools]).to include('gitlab_search')
            expect(result.payload[:pre_approved_tools]).not_to include('gitlab_search')
          end
        end

        context 'with an allow rule on a destructive MCP-only tool' do
          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'manage_pipeline', web_access: :allow)
          end

          it 'pre-approves the prefixed spelling' do
            expect(result.payload[:pre_approved_tools]).to include('gitlab_manage_pipeline')
          end

          it 'does not grant the MCP privilege group' do
            expect(result.payload[:pre_approved_agent_privileges])
              .not_to include(::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_MCP_TOOLS)
          end
        end

        context 'with a project rule stricter than the namespace rule' do
          let_it_be(:project) { create(:project, group: namespace) }

          subject(:service) do
            described_class.new(namespace: namespace, surface: surface, project: project)
          end

          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'search', web_access: :allow)
            create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'search',
              web_access: :deny)
          end

          it 'lets the project deny win over the namespace allow' do
            expect(result.payload[:denied_tools]).to include('gitlab_search')
            expect(result.payload[:pre_approved_tools]).not_to include('gitlab_search')
          end
        end
      end
    end
  end
end
