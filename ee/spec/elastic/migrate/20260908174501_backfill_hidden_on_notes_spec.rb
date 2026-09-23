# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260908174501_backfill_hidden_on_notes.rb')

RSpec.describe BackfillHiddenOnNotes, :elastic_delete_by_query, :sidekiq_inline,
  feature_category: :global_search do
  include_examples 'migration backfills fields' do
    let_it_be(:project) { create(:project) }
    let(:version) { 20260908174501 }
    let(:expected_throttle_delay) { 1.minute }
    let(:expected_batch_size) { 9000 }
    let(:objects) { create_list(:note, 3, project: project) }
    let(:expected_fields) { { hidden: false } }
  end
end
