# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe API::Helpers::SearchHelpers, feature_category: :global_search do
  describe '.global_search_scopes' do
    it 'returns the expected scopes' do
      expect(described_class.global_search_scopes).to match_array(
        %w[wiki_blobs blobs commits notes projects groups issues work_items merge_requests milestones
          snippet_titles users]
      )
    end
  end

  describe '.group_search_scopes' do
    it 'returns the expected scopes' do
      expect(described_class.group_search_scopes)
        .to match_array(%w[wiki_blobs blobs commits notes projects groups issues work_items merge_requests
          milestones users])
    end
  end

  describe '.search_param_keys' do
    it 'returns param keys with fields' do
      expect(described_class.search_param_keys).to match_array(
        %i[
          author_username confidential exclude_forks fields include_archived label_name num_context_lines order_by
          page per_page regex scope search search_type sort source_branch state target_branch type
        ]
      )
    end
  end

  describe '.search_negated_param_keys' do
    it 'returns only the negatable merge request filters' do
      expect(described_class.search_negated_param_keys).to match_array(%i[author_username source_branch target_branch])
    end
  end

  describe '.gitlab_search_mcp_params' do
    it 'carries the merge request filters in the MCP input schema, and no negated form' do
      expect(described_class.gitlab_search_mcp_params)
        .to include(:source_branch, :target_branch, :author_username, :label_name)
      expect(described_class.gitlab_search_mcp_params).not_to include(:not)
    end
  end
end
