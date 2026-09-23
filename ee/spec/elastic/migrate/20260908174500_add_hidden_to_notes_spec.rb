# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260908174500_add_hidden_to_notes.rb')

RSpec.describe AddHiddenToNotes, :elastic, feature_category: :global_search do
  let(:version) { 20260908174500 }

  include_examples 'migration adds mapping'

  # The shared example above never inspects the mapping body, so it would pass
  # for any `new_mappings` whatsoever.
  describe 'the mapping body' do
    let(:migration) { described_class.new(version) }
    let(:helper) { ::Search::Elastic::Helper.new }

    before do
      allow(migration).to receive(:helper).and_return(helper)
      allow(helper).to receive(:get_mapping).and_return({})
    end

    it 'adds a boolean hidden field to the notes index' do
      expect(helper).to receive(:update_mapping).with(
        index_name: Note.__elasticsearch__.index_name,
        mappings: { properties: { hidden: { type: 'boolean' } } }
      )

      migration.migrate
    end
  end
end
