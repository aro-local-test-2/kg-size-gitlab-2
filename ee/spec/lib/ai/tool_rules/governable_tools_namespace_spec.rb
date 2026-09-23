# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'governable MCP tools resolve a namespace', feature_category: :ai_agents do
  let_it_be(:namespace) { create(:group) }

  let(:governed_tools) do
    ::Ai::ToolRules::GovernedMcpTools.for(namespace)
  end

  let(:manager) { ::Mcp::Tools::Manager.new }

  before do
    stub_feature_flags(duo_mcp_tool_governance: namespace)
  end

  it 'declares a namespace argument for every governable tool' do
    missing = governed_tools.names.reject do |name|
      manager.list_tools[name].ungovernable? || manager.list_tools[name].namespace_arguments.present?
    end

    expect(missing).to be_empty,
      "these tools are governable but declare no scope, so their rules are never enforced: #{missing.join(', ')}"
  end

  it 'declares at least one argument the tool actually accepts' do
    unresolvable = governed_tools.names.reject do |name|
      tool = manager.list_tools[name]
      next true if tool.ungovernable?

      schema = tool.input_schema
      accepted = (schema[:properties] || schema['properties'] || {}).keys.map(&:to_s)

      (tool.namespace_arguments.values.map(&:to_s) & accepted).any?
    end

    expect(unresolvable).to be_empty,
      "these tools declare no scope argument they accept, so their rules never apply: #{unresolvable.join(', ')}"
  end

  it 'keys every declaration on a kind the resolver reads' do
    recognized = ::Mcp::Tools::Concerns::GovernanceNamespaceResolver::CONTAINER_KINDS

    unknown = governed_tools.names.filter_map do |name|
      keys = manager.list_tools[name].namespace_arguments.keys - recognized
      "#{name} (#{keys.join(', ')})" if keys.any?
    end

    expect(unknown).to be_empty,
      "these tools declare a namespace kind nothing resolves, so they are never governed: #{unknown.join(', ')}"
  end
end
