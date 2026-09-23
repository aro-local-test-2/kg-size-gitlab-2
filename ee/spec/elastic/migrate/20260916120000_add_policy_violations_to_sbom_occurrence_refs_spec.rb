# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260916120000_add_policy_violations_to_sbom_occurrence_refs.rb')

RSpec.describe AddPolicyViolationsToSbomOccurrenceRefs, :elastic, feature_category: :dependency_management do
  let(:version) { 20260916120000 }

  include_examples 'migration adds mapping'

  # The shared example above stubs #get_mapping and only asserts that update_mapping is called, so it
  # would pass for any new_mappings whatsoever.
  describe 'the mapping body' do
    let(:migration) { described_class.new(version) }
    let(:helper) { ::Search::Elastic::Helper.new }

    before do
      allow(migration).to receive(:helper).and_return(helper)
      allow(helper).to receive(:get_mapping).and_return({})
    end

    it 'adds a short policy_violations field to the sbom_occurrence_refs index' do
      expect(helper).to receive(:update_mapping).with(
        index_name: ::Search::Elastic::Types::Sbom::OccurrenceRef.index_name,
        mappings: { properties: { policy_violations: { type: 'short' } } }
      )

      migration.migrate
    end
  end
end
