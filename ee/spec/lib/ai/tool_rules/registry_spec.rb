# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::Registry, feature_category: :duo_agent_platform do
  before do
    described_class.instance_variable_set(:@catalog_tool_names, nil)
    described_class.instance_variable_set(:@all_tool_names, nil)
    described_class.instance_variable_set(:@action_type_for, nil)
  end

  describe 'PRIVILEGE_GROUP_MAPPING' do
    it 'contains no duplicate tool names within a group' do
      described_class::PRIVILEGE_GROUP_MAPPING.each do |group, tools|
        expect(tools.uniq).to eq(tools), "Duplicate tool names found in #{group}"
      end
    end

    it 'contains no duplicate tool names across groups' do
      all_tools = described_class::PRIVILEGE_GROUP_MAPPING.values.flatten

      expect(all_tools.uniq).to eq(all_tools)
    end

    it 'contains only non-empty strings' do
      described_class::PRIVILEGE_GROUP_MAPPING.each do |group, tools|
        expect(tools).to all(be_a(String).and(be_present)), "Non-empty string check failed in #{group}"
      end
    end
  end

  describe '.catalog_tool_names' do
    it 'returns tool names from the catalog' do
      expect(described_class.catalog_tool_names).to include('create_issue', 'read_file', 'run_command')
    end

    it 'returns only strings' do
      expect(described_class.catalog_tool_names).to all(be_a(String))
    end
  end

  describe '.all_tool_names' do
    it 'only includes tools that are mapped in PRIVILEGE_GROUP_MAPPING' do
      expect(described_class.all_tool_names).to all(satisfy { |name|
        described_class::PRIVILEGE_GROUP_FOR.key?(name)
      })
    end

    it 'excludes catalog tools that have no privilege group mapping' do
      unmapped = described_class.catalog_tool_names - described_class::PRIVILEGE_GROUP_FOR.keys

      expect(described_class.all_tool_names).not_to include(*unmapped) if unmapped.any?
    end
  end

  describe '.governed_tool_names_for' do
    it 'excludes mapped names that have no catalog entry' do
      governed = described_class.governed_tool_names_for(group_name: :read_write_gitlab)

      expect(governed).to include('create_issue')
      expect(governed).not_to include('set_form_permissions')
      expect(governed).to all(be_in(described_class.all_tool_names))
    end

    it 'returns the full mapping for a fully cataloged group' do
      expect(described_class.governed_tool_names_for(group_name: :use_git)).to eq(%w[run_git_command])
    end

    it 'returns an empty array for a group with an empty mapping' do
      expect(described_class.governed_tool_names_for(group_name: :run_mcp_tools)).to eq([])
    end

    it 'returns an empty array for an unknown group' do
      expect(described_class.governed_tool_names_for(group_name: :not_a_group)).to eq([])
    end
  end

  describe 'mapping/catalog divergence' do
    let(:unruleable_tools) do
      %w[
        ascp_create_component
        ascp_create_scan
        ascp_create_security_context
        ascp_list_components
        ascp_list_scans
        evaluate_vuln_fp_status
        post_secret_fp_analysis_to_gitlab
        set_form_permissions
      ]
    end

    it 'pins the mapped tools that have no catalog entry (no rule can exist for them)' do
      divergent = described_class::PRIVILEGE_GROUP_FOR.keys - described_class.catalog_tool_names

      expect(divergent).to match_array(unruleable_tools), <<~MSG
        The set of mapped-but-uncataloged tools changed. These names cannot carry
        Ai::ToolRule rows and are excluded from governed_tool_names_for, which
        controls when a privilege group counts as fully configured
        (ResolutionService#resolve_group). If you cataloged one of these tools or
        removed one from the catalog, update this list deliberately: it changes
        the pre-approval threshold for existing namespaces.
      MSG
    end
  end

  describe 'PRIVILEGE_GROUP_FOR' do
    it 'maps every tool name to a privilege group' do
      expect(described_class.all_tool_names).to all(satisfy { |name|
        described_class::PRIVILEGE_GROUP_FOR[name].present?
      })
    end

    it 'maps to a key that exists in PRIVILEGE_GROUP_MAPPING' do
      expect(described_class::PRIVILEGE_GROUP_FOR.values).to all(satisfy { |group|
        described_class::PRIVILEGE_GROUP_MAPPING.key?(group)
      })
    end
  end

  describe '.action_type_for' do
    it 'maps every tool name to an action type' do
      expect(described_class.all_tool_names).to all(satisfy { |name|
        described_class.action_type_for[name].present?
      })
    end

    it 'only maps to valid action types' do
      valid_types = described_class::ACTION_TYPE_GROUPS.keys

      expect(described_class.action_type_for.values).to all(be_in(valid_types))
    end

    it 'maps read_only_gitlab tools to :read' do
      tools = described_class::PRIVILEGE_GROUP_MAPPING[:read_only_gitlab] & described_class.all_tool_names

      expect(tools).to all(satisfy { |name|
        described_class.action_type_for[name] == :read
      })
    end

    it 'maps read_only_files tools to :read' do
      tools = described_class::PRIVILEGE_GROUP_MAPPING[:read_only_files] & described_class.all_tool_names

      expect(tools).to all(satisfy { |name|
        described_class.action_type_for[name] == :read
      })
    end

    it 'maps read_write_files tools to :write' do
      tools = described_class::PRIVILEGE_GROUP_MAPPING[:read_write_files] & described_class.all_tool_names

      expect(tools).to all(satisfy { |name|
        described_class.action_type_for[name] == :write
      })
    end

    it 'maps run_commands tools to :destroy' do
      tools = described_class::PRIVILEGE_GROUP_MAPPING[:run_commands] & described_class.all_tool_names

      expect(tools).to all(satisfy { |name|
        described_class.action_type_for[name] == :destroy
      })
    end

    it 'maps use_git tools to :destroy' do
      tools = described_class::PRIVILEGE_GROUP_MAPPING[:use_git] & described_class.all_tool_names

      expect(tools).to all(satisfy { |name|
        described_class.action_type_for[name] == :destroy
      })
    end
  end

  describe 'CATEGORY_FOR_GROUP' do
    it 'has a category for every privilege group' do
      described_class::PRIVILEGE_GROUP_MAPPING.each_key do |group|
        expect(described_class::CATEGORY_FOR_GROUP).to have_key(group),
          "No category defined for privilege group #{group}"
      end
    end

    it 'contains only non-empty strings' do
      expect(described_class::CATEGORY_FOR_GROUP.values).to all(be_a(String).and(be_present))
    end
  end

  describe '.source_for' do
    it 'returns "gitlab" for a standard GitLab tool' do
      expect(described_class.source_for('create_issue')).to eq('gitlab')
    end

    it 'returns "gitlab" for a file tool' do
      expect(described_class.source_for('read_file')).to eq('gitlab')
    end

    it 'returns "gitlab" for an unknown tool name' do
      expect(described_class.source_for('unknown_tool')).to eq('gitlab')
    end
  end

  describe '.default_permission_for' do
    it 'returns "ask" with no arguments' do
      expect(described_class.default_permission_for).to eq('ask')
    end

    it 'returns "allow" for a tool in a preapproved group' do
      read_tool = described_class::PRIVILEGE_GROUP_MAPPING[:read_only_gitlab].first
      expect(described_class.default_permission_for(tool_name: read_tool)).to eq('allow')
    end

    it 'returns "ask" for a tool not in a preapproved group' do
      write_tool = described_class::PRIVILEGE_GROUP_MAPPING[:read_write_gitlab].first
      expect(described_class.default_permission_for(tool_name: write_tool)).to eq('ask')
    end

    context 'when group_name is provided directly' do
      it 'returns "allow" for the read-only GitLab group' do
        expect(described_class.default_permission_for(group_name: :read_only_gitlab)).to eq('allow')
      end

      it 'returns "ask" for the read-only files group (local filesystem, least privilege)' do
        expect(described_class.default_permission_for(group_name: :read_only_files)).to eq('ask')
      end

      it 'returns "ask" for the read-write files group (includes command execution)' do
        expect(described_class.default_permission_for(group_name: :read_write_files)).to eq('ask')
      end

      it 'returns "ask" for the run_commands (destroy) group' do
        expect(described_class.default_permission_for(group_name: :run_commands)).to eq('ask')
      end

      it 'returns "ask" for the use_git (destroy) group' do
        expect(described_class.default_permission_for(group_name: :use_git)).to eq('ask')
      end

      it 'returns "ask" for a non-preapproved group' do
        expect(described_class.default_permission_for(group_name: :read_write_gitlab)).to eq('ask')
      end
    end

    it 'gives group_name precedence when both tool_name and group_name are provided' do
      read_tool = described_class::PRIVILEGE_GROUP_MAPPING[:read_only_gitlab].first

      expect(described_class.default_permission_for(tool_name: read_tool, group_name: :read_write_gitlab)).to eq('ask')
    end

    it 'returns "ask" for an unmapped tool name' do
      expect(described_class.default_permission_for(tool_name: 'not_a_real_tool')).to eq('ask')
    end
  end

  describe 'catalog coverage' do
    it 'has every catalog tool either mapped or explicitly opted out' do
      mapped = described_class::PRIVILEGE_GROUP_FOR.keys
      opted_out = described_class::UNGOVERNED_TOOLS # see point 2
      unaccounted = described_class.catalog_tool_names - mapped - opted_out

      expect(unaccounted).to be_empty, <<~MSG
        New catalog tools detected without a privilege group:
          #{unaccounted.join("\n  ")}

        Add each tool to the appropriate group in
        ee/lib/ai/tool_rules/registry.rb (PRIVILEGE_GROUP_MAPPING),
        or to UNGOVERNED_TOOLS if it is intentionally ungovernable.
      MSG
    end
  end

  describe '.to_mcp_tool_names' do
    it 'maps known catalog names to their MCP names' do
      expect(described_class.to_mcp_tool_names(['create_issue'])).to match_array(['create_work_item'])
    end

    it 'passes unknown catalog names through unchanged' do
      expect(described_class.to_mcp_tool_names(['unknown_tool'])).to match_array(['unknown_tool'])
    end

    it 'handles a mix of known and unknown names' do
      expect(described_class.to_mcp_tool_names(%w[create_issue unknown_tool get_issue]))
        .to match_array(%w[create_work_item unknown_tool get_issue])
    end
  end

  describe 'catalog aliases declared on MCP tools' do
    it 'never gives a served catalog tool a second catalog identity' do
      ambiguous = served_mcp_tool_names.select do |tool_name|
        described_class::PRIVILEGE_GROUP_FOR.key?(tool_name) && catalog_twins_of(tool_name).any?
      end

      expect(ambiguous).to be_empty, <<~MSG
        These MCP tools are governed catalog tools in their own right and also declare a
        catalog name as a `tool_alias`, so which rule governs them is ambiguous:
          #{ambiguous.join("\n  ")}

        Drop the alias, or rename the MCP tool so it is not a catalog name.
      MSG
    end
  end

  # Each helper must answer exactly what its pre-existing counterpart answered.
  describe 'MCP-aware helpers with no catalog' do
    it 'lists exactly the catalog tool names' do
      expect(described_class.rulable_tool_names).to eq(described_class.all_tool_names)
      expect(described_class.rulable_tool_names(mcp_tools: nil)).to eq(described_class.all_tool_names)
      expect(described_class.rulable_tool_names(mcp_tools: Ai::ToolRules::GovernedMcpTools.none))
        .to eq(described_class.all_tool_names)
    end

    it 'emits the same names as the rename-only mapping' do
      names = %w[create_issue get_issue run_command]

      expect(described_class.to_mcp_tool_names(names, mcp_tools: Ai::ToolRules::GovernedMcpTools.none))
        .to eq(described_class.to_mcp_tool_names(names))
    end

    it 'reports source, action type and category from the privilege group alone' do
      expect(described_class.source_for('get_issue')).to eq('gitlab')
      expect(described_class.action_type_of('get_issue')).to eq(:read)
      expect(described_class.category_for('get_issue')).to eq('GitLab Read')
    end

    it 'reports nothing for a name no privilege group covers' do
      expect(described_class.action_type_of('search')).to be_nil
      expect(described_class.category_for('search')).to be_nil
    end
  end

  describe 'MCP-aware helpers with a catalog' do
    let(:mcp_tools) do
      instance_double(
        Ai::ToolRules::GovernedMcpTools,
        empty?: false,
        rulable_names: %w[search manage_pipeline]
      )
    end

    before do
      allow(mcp_tools).to receive(:action_type_for).with('search').and_return(:read)
      allow(mcp_tools).to receive(:action_type_for).with('manage_pipeline').and_return(:destroy)
      allow(mcp_tools).to receive(:spellings_for).and_return([])
      allow(mcp_tools).to receive(:spellings_for).with('search').and_return(['gitlab_search'])
      allow(mcp_tools).to receive(:spellings_for)
        .with('get_work_item_notes').and_return(['gitlab_get_workitem_notes'])
      allow(mcp_tools).to receive(:spellings_for)
        .with('get_merge_request').and_return(['gitlab_get_merge_request'])
      allow(mcp_tools).to receive(:spellings_for)
        .with('create_issue').and_return(['gitlab_create_issue'])
      allow(mcp_tools).to receive(:spellings_for)
        .with('create_work_item').and_return(['gitlab_save_work_item'])
    end

    it 'adds MCP-only names to the rulable set without disturbing catalog names' do
      expect(described_class.rulable_tool_names(mcp_tools: mcp_tools))
        .to eq(described_class.all_tool_names + %w[search manage_pipeline])
    end

    it 'labels MCP-only tools with the MCP source and category' do
      expect(described_class.source_for('search', mcp_tools: mcp_tools)).to eq('mcp')
      expect(described_class.category_for('search', mcp_tools: mcp_tools)).to eq('MCP')
      expect(described_class.action_type_of('search', mcp_tools: mcp_tools)).to eq(:read)
      expect(described_class.action_type_of('manage_pipeline', mcp_tools: mcp_tools)).to eq(:destroy)
    end

    it 'leaves catalog tools labelled by their privilege group' do
      expect(described_class.source_for('get_issue', mcp_tools: mcp_tools)).to eq('gitlab')
      expect(described_class.category_for('get_issue', mcp_tools: mcp_tools)).to eq('GitLab Read')
      expect(described_class.action_type_of('get_issue', mcp_tools: mcp_tools)).to eq(:read)
    end

    describe '.to_mcp_tool_names' do
      # The bare name of an MCP-only tool addresses nothing: no catalog tool answers to
      # it, and the Duo Workflow Service knows the MCP tool by its prefixed spelling.
      it 'emits only the prefixed spelling of an MCP-only tool' do
        expect(described_class.to_mcp_tool_names(['search'], mcp_tools: mcp_tools))
          .to contain_exactly('gitlab_search')
      end

      it 'keeps the bare name of a catalog tool the MCP server also serves' do
        expect(described_class.to_mcp_tool_names(['get_merge_request'], mcp_tools: mcp_tools))
          .to contain_exactly('get_merge_request', 'gitlab_get_merge_request')
      end

      it 'adds the prefixed MCP spelling of an aliased catalog capability' do
        expect(described_class.to_mcp_tool_names(['get_work_item_notes'], mcp_tools: mcp_tools))
          .to contain_exactly('get_work_item_notes', 'gitlab_get_workitem_notes')
      end

      it 'keeps the rename and adds nothing for a name the MCP server does not serve' do
        expect(described_class.to_mcp_tool_names(['run_command'], mcp_tools: mcp_tools))
          .to contain_exactly('run_command')
      end

      # `create_issue` renames to `create_work_item`, which `save_work_item` answers for,
      # so this one capability reaches the MCP server under two names.
      it 'reaches both transports of a renamed capability' do
        expect(described_class.to_mcp_tool_names(['create_issue'], mcp_tools: mcp_tools))
          .to contain_exactly('create_work_item', 'gitlab_create_issue', 'gitlab_save_work_item')
      end
    end
  end

  describe 'MCP server tool prefix' do
    # `gitlab_` is both the MCP server prefix and a legitimate catalog name prefix. If
    # the MCP server ever serves `api_get`, its prefixed spelling would collide with the
    # distinct catalog identity `gitlab_api_get` and the two governance domains would
    # silently fuse.
    it 'cannot produce a name that collides with a catalog identity' do
      prefix = ::Ai::DuoWorkflows::McpConfigService::MCP_SERVER_TOOL_PREFIX
      catalog_names = described_class::PRIVILEGE_GROUP_FOR.keys
      shadowed = catalog_names.select { |name| name.start_with?(prefix) }
        .map { |name| name.delete_prefix(prefix) }

      collisions = shadowed & served_mcp_tool_names

      expect(collisions).to be_empty, <<~MSG
        These MCP tools would be emitted under a name that already identifies a
        different catalog tool:
          #{collisions.map { |name| "#{name} -> #{prefix}#{name}" }.join("\n  ")}

        Rename the MCP tool, or declare the catalog name as a `tool_alias` on it so one
        rule governs both.
      MSG
    end
  end

  describe 'served MCP tool coverage' do
    # Governance reaches these capabilities only through the alias the MCP tool declares,
    # so dropping one stops enforcing the rule on its catalog name. Adding a tool does not
    # touch this list.
    governance_aliases = {
      'create_branch' => 'add_branch',
      'create_commit' => 'add_commit',
      'create_merge_request' => 'save_merge_request',
      'create_merge_request_note' => 'save_note',
      'create_work_item' => 'save_work_item',
      'create_work_item_note' => 'save_note',
      'get_work_item_notes' => 'get_workitem_notes',
      'gitlab_merge_request_search' => 'list_merge_requests',
      'list_all_merge_request_notes' => 'get_merge_request_notes',
      'list_merge_request_diffs' => 'get_merge_request_diffs',
      'update_merge_request' => 'save_merge_request',
      'update_work_item' => 'save_work_item'
    }.freeze

    it 'keeps every alias governance depends on' do
      broken = governance_aliases.reject do |catalog_name, mcp_tool_name|
        served_mcp_manager.alias_map[catalog_name] == mcp_tool_name
      end

      expect(broken).to be_empty, <<~MSG
        Removing this alias breaks governance enforcement, because the rule on the catalog
        name is what reaches the MCP tool:
          #{broken.map { |catalog, mcp| "#{catalog} was served by #{mcp}" }.join("\n  ")}

        Restore the `tool_aliases` declaration, or drop the pair here once the capability
        itself is gone.
      MSG
    end

    it 'has risk annotations declared on every served tool' do
      unannotated = served_mcp_tools.reject do |tool_name, tool|
        next true if catalog_twins_of(tool_name).any?
        next true if described_class::PRIVILEGE_GROUP_FOR.key?(tool_name)

        tool.annotations.to_h.key?(:readOnlyHint)
      end.keys

      expect(unannotated).to be_empty, <<~MSG
        These MCP tools declare no readOnlyHint annotation, so governance can only
        assume the most restrictive class for them:
          #{unannotated.join("\n  ")}

        Declare `annotations: { readOnlyHint: ..., destructiveHint: ... }` on each
        tool's register_version payload or its `route_setting :mcp`.
      MSG
    end
  end

  def served_mcp_manager
    @served_mcp_manager ||= begin
      ::API::API.send(:reset_routes!)
      ::Mcp::Tools::Manager.new
    end
  end

  def served_mcp_tools
    @served_mcp_tools ||= served_mcp_manager.list_tools.reject { |_name, tool| tool.unlisted? }
  end

  # The catalog capabilities a served tool answers for, mirroring GovernedMcpTools.
  def catalog_twins_of(tool_name)
    served_mcp_manager.aliases_for(tool_name)
      .select { |name| described_class::PRIVILEGE_GROUP_FOR.key?(name) }
  end

  def served_mcp_tool_names
    served_mcp_tools.keys
  end
end
