# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::GovernedMcpTools, feature_category: :duo_agent_platform do
  let_it_be(:namespace) { create(:group) }

  # Covers each annotation shape plus one catalog twin, one alias spelling and one
  # unlisted tool, so the skip rules and the derivation ladder are exercised together.
  let(:served_tools) do
    {
      'search' => tool_double({ readOnlyHint: true }),
      'save_work_item' => tool_double({ readOnlyHint: false, destructiveHint: false }),
      'manage_pipeline' => tool_double({ readOnlyHint: false, destructiveHint: true }),
      'mystery_tool' => tool_double,
      'confused_tool' => tool_double({ readOnlyHint: true, destructiveHint: true }),
      'get_merge_request' => tool_double({ readOnlyHint: true }),
      'get_workitem_notes' => tool_double({ readOnlyHint: true }),
      'run_asc_scan' => tool_double({ readOnlyHint: false, destructiveHint: false }),
      'set_form_permissions' => tool_double({ readOnlyHint: false, destructiveHint: false }),
      'hidden_tool' => tool_double({ readOnlyHint: true }, unlisted: true)
    }
  end

  let(:tool_aliases) do
    {
      'search' => ['gitlab_search'],
      'save_work_item' => %w[create_work_item update_work_item],
      'get_workitem_notes' => ['get_work_item_notes'],
      'run_asc_scan' => ['ascp_create_scan']
    }
  end

  def tool_double(annotations = {}, unlisted: false)
    instance_double(Mcp::Tools::Base::BaseService, annotations: annotations, unlisted?: unlisted)
  end

  before do
    manager = instance_double(::Mcp::Tools::Manager, list_tools: served_tools)
    allow(manager).to receive(:aliases_for) { |name| tool_aliases.fetch(name, []) }
    allow(::Mcp::Tools::Manager).to receive(:new).and_return(manager)
  end

  describe '.for' do
    subject(:catalog) { described_class.for(namespace) }

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(duo_mcp_tool_governance: false)
      end

      it 'is empty and never builds the manager' do
        expect(::Mcp::Tools::Manager).not_to receive(:new)

        expect(catalog).to be_empty
        expect(catalog.rulable_names).to be_empty
        expect(catalog.spellings_for('search')).to be_empty
      end
    end

    context 'when the namespace is nil' do
      it 'is empty' do
        expect(described_class.for(nil)).to be_empty
      end
    end

    context 'when the feature flag is enabled' do
      before do
        stub_feature_flags(duo_mcp_tool_governance: namespace)
      end

      it 'derives the action type from each tool\'s own annotations' do
        expect(catalog.action_type_for('search')).to eq(:read)
        expect(catalog.action_type_for('save_work_item')).to eq(:write)
        expect(catalog.action_type_for('manage_pipeline')).to eq(:destroy)
      end

      it 'treats a tool declaring no annotations as the most restrictive class' do
        expect(catalog.action_type_for('mystery_tool')).to eq(:destroy)
      end

      # Contradictory, but nothing stops a tool declaring both.
      it 'treats a tool declaring both hints as destructive' do
        expect(catalog.action_type_for('confused_tool')).to eq(:destroy)
      end

      it 'keeps unlisted tools governed, because they are hidden from tools/list but stay callable' do
        expect(catalog.action_type_for('hidden_tool')).to eq(:read)
        expect(catalog.rulable_names).to include('hidden_tool')
      end

      describe '#rulable_names' do
        it 'covers only capabilities with no catalog twin' do
          expect(catalog.rulable_names).to contain_exactly(
            'search', 'manage_pipeline', 'mystery_tool', 'confused_tool',
            'run_asc_scan', 'set_form_permissions', 'hidden_tool'
          )
        end

        it 'excludes a served name that is itself a governed catalog tool' do
          expect(catalog.rulable_names).not_to include('get_merge_request')
        end

        it 'excludes a served name that aliases a catalog capability' do
          expect(catalog.rulable_names).not_to include('get_workitem_notes', 'save_work_item')
        end

        it 'keeps a tool whose only alias is a rename rather than a catalog name' do
          expect(catalog.rulable_names).to include('search')
        end

        # Both names are mapped but uncataloged, so no rule can be written against them.
        # Treating either as a catalog twin would leave the MCP tool with no reachable rule.
        it 'keeps a tool whose only alias is a mapped but uncataloged name' do
          expect(catalog.rulable_names).to include('run_asc_scan')
        end

        it 'keeps a tool named after a mapped but uncataloged tool' do
          expect(catalog.rulable_names).to include('set_form_permissions')
        end
      end

      describe '#spellings_for' do
        it 'prefixes an MCP-only tool with the server name' do
          expect(catalog.spellings_for('search')).to contain_exactly('gitlab_search')
        end

        it 'reaches the MCP transport of a catalog tool served under the same name' do
          expect(catalog.spellings_for('get_merge_request')).to contain_exactly('gitlab_get_merge_request')
        end

        it 'reaches the MCP spelling of an aliased catalog capability' do
          expect(catalog.spellings_for('get_work_item_notes'))
            .to contain_exactly('gitlab_get_workitem_notes')
        end

        it 'reaches one MCP tool from every catalog capability it answers for' do
          expect(catalog.spellings_for('create_work_item')).to contain_exactly('gitlab_save_work_item')
          expect(catalog.spellings_for('update_work_item')).to contain_exactly('gitlab_save_work_item')
        end

        it 'returns nothing for a governed name the MCP server does not serve' do
          expect(catalog.spellings_for('run_command')).to be_empty
        end
      end

      context 'with a request store', :request_store do
        it 'builds the manager once and reuses the result' do
          expect(::Mcp::Tools::Manager).to receive(:new).once.and_call_original

          expect(described_class.for(namespace)).to equal(described_class.for(namespace))
        end
      end
    end
  end

  describe '.none' do
    it 'answers every query as empty' do
      catalog = described_class.none

      expect(catalog).to be_empty
      expect(catalog.rulable_names).to be_empty
      expect(catalog.action_type_for('search')).to be_nil
      expect(catalog.spellings_for('search')).to be_empty
    end
  end
end
