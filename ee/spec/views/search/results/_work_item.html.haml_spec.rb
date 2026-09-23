# frozen_string_literal: true

require 'spec_helper'

# The EE partial only owns the legacy-epic branch (:5-31); the else branch delegates to
# the CE template, which has no view spec of its own. The work_items scope context in
# spec/views/search/_results.html.haml_spec.rb is its only view-spec cover.
RSpec.describe 'search/results/_work_item', feature_category: :global_search do
  let_it_be(:group) { build_stubbed(:group) }
  let_it_be(:author) { build_stubbed(:user) }
  let_it_be(:epic) { build_stubbed(:epic, group: group, author: author, title: 'Test epic') }

  before do
    assign(:scope, 'epics')
    assign(:search_term, 'Test')
    assign(:search_highlight, {})

    allow(view).to receive_messages(
      group_epic_path: '/some/path',
      highlight_and_truncate_issuable: 'Test description'
    )
    allow(epic).to receive(:labels).and_return([])
  end

  context 'when no search request ID was minted' do
    it 'renders no join key on the legacy epic link' do
      render partial: 'search/results/work_item', locals: { result: epic, index: 0 }

      expect(rendered).to have_css("[data-event-tracking='click_search_result']")
      expect(rendered).not_to have_css('[data-event-property]')
    end
  end

  context 'when a search request ID was minted' do
    let(:search_request_id) { '11111111-2222-3333-4444-555555555555' }

    before do
      assign(:search_request_id, search_request_id)
    end

    it 'puts the join key on the legacy epic link' do
      render partial: 'search/results/work_item', locals: { result: epic, index: 0 }

      properties = tracked_link_properties(rendered)

      # One partial, one link: this proves the helper reaches this call site, not that
      # the attribute is applied per row.
      expect(properties).to eq([search_request_id])
    end
  end
end
