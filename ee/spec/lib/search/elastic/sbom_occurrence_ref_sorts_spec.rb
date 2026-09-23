# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ::Search::Elastic::SbomOccurrenceRefSorts, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let(:query_hash) { {} }

  subject(:sort_by) { described_class.sort_by(query_hash: query_hash, options: options) }

  describe '.sort_by' do
    where(:sort_by_param, :sort_param, :expected) do
      'name'                             | 'asc'  | { component_name: { order: :asc } }
      'name'                             | 'desc' | { component_name: { order: :desc } }
      'component_name'                   | 'asc'  | { component_name: { order: :asc } }
      'packager'                         | 'asc'  | { package_manager: { order: :asc } }
      'package_manager'                  | 'desc' | { package_manager: { order: :desc } }
      'severity'                         | 'asc'  | { highest_severity: { order: :asc } }
      'highest_severity'                 | 'desc' | { highest_severity: { order: :desc } }
      'license'                          | 'asc'  | { primary_license_spdx_identifier: { order: :asc } }
      'primary_license_spdx_identifier'  | 'desc' | { primary_license_spdx_identifier: { order: :desc } }
    end

    with_them do
      let(:options) { { sort_by: sort_by_param, sort: sort_param } }

      it 'sorts on the mapped field and breaks ties on the occurrence id' do
        expect(sort_by[:sort]).to eq(expected.merge(sbom_occurrence_id: { order: :asc }))
      end
    end

    context 'when the sort direction is absent or unrecognised' do
      let(:options) { { sort_by: 'name', sort: 'sideways' } }

      it 'sorts ascending' do
        expect(sort_by[:sort]).to eq(
          component_name: { order: :asc }, sbom_occurrence_id: { order: :asc }
        )
      end
    end

    context 'when sort_by is absent' do
      let(:options) { {} }

      it 'sorts on the occurrence id alone' do
        expect(sort_by[:sort]).to eq(sbom_occurrence_id: { order: :asc })
      end
    end

    context 'when sort_by is unrecognised' do
      let(:options) { { sort_by: 'bogus', sort: 'desc' } }

      it 'sorts on the occurrence id alone' do
        expect(sort_by[:sort]).to eq(sbom_occurrence_id: { order: :asc })
      end
    end

    it 'leaves the rest of the query_hash alone' do
      expect(described_class.sort_by(query_hash: { size: 5 }, options: { sort_by: 'name' }))
        .to include(size: 5)
    end
  end
end
