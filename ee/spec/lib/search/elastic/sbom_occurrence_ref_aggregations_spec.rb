# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ::Search::Elastic::SbomOccurrenceRefAggregations, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let(:query_hash) { { query: { bool: { filter: [] } } } }

  describe '.by_component_and_version' do
    subject(:by_component_and_version) do
      described_class.by_component_and_version(query_hash: query_hash, options: options)
    end

    let(:options) { { aggregate_by_component_and_version: true } }

    context 'when options[:aggregate_by_component_and_version] is not set' do
      let(:options) { {} }

      it 'does not modify the query_hash' do
        expect(by_component_and_version).to eq(query_hash)
      end
    end

    it 'sets size to 0 so that no hits are returned' do
      expect(by_component_and_version[:size]).to eq(0)
    end

    it 'keeps the existing query' do
      expect(by_component_and_version[:query]).to eq(query_hash[:query])
    end

    it 'aggregates only the id used to hydrate the record' do
      expect(by_component_and_version.dig(:aggs, :dependencies, :aggs)).to eq(
        occurrence_id: { min: { field: :sbom_occurrence_id } }
      )
    end

    describe 'after key' do
      subject(:composite) { by_component_and_version.dig(:aggs, :dependencies, :composite) }

      context 'when no cursor is given' do
        it 'does not set an after key, so the first page is returned' do
          expect(composite).not_to have_key(:after)
        end
      end

      context 'when a cursor is given' do
        let(:after_key) { { highest_severity: 7, component_id: 1, component_version_id: 10 } }
        let(:options) { super().merge(after_key: after_key) }

        it 'resumes the composite from that key' do
          expect(composite[:after]).to eq(after_key)
        end
      end

      # Elasticsearch counts the values in `after` against the sources, so a nil has to be kept rather
      # than compacted away.
      context 'when the cursor holds a nil value' do
        let(:after_key) { { highest_severity: nil, component_id: 1, component_version_id: nil } }
        let(:options) { super().merge(after_key: after_key) }

        it 'keeps the nil values' do
          expect(composite[:after]).to eq(after_key)
        end
      end

      context 'when the cursor is empty' do
        let(:options) { super().merge(after_key: {}) }

        it 'does not set an after key' do
          expect(composite).not_to have_key(:after)
        end
      end
    end

    describe 'sources' do
      subject(:sources) { by_component_and_version.dig(:aggs, :dependencies, :composite, :sources) }

      context 'when no sort is given' do
        it 'groups by component and version in ascending order' do
          expect(sources).to eq(
            [
              { component_id: { terms: { field: :component_id, order: :asc, missing_bucket: false } } },
              { component_version_id: { terms: { field: :component_version_id, order: :asc,
                                                 missing_bucket: true, missing_order: :last } } }
            ]
          )
        end
      end

      context 'when sort_by is not supported' do
        let(:options) { super().merge(sort_by: 'unsupported') }

        it 'falls back to grouping by component and version' do
          expect(sources.flat_map(&:keys)).to eq(%i[component_id component_version_id])
        end
      end

      context 'when a sort_by is given' do
        let(:options) { super().merge(sort_by: sort_by, sort: 'desc') }

        # highest_severity carries no missing_order: Elasticsearch's default already matches the
        # nulls_last-descending that ::Sbom::AggregationsFinder applies to that column alone.
        where(:sort_by, :field, :missing_order) do
          'severity'                        | :highest_severity                | nil
          'highest_severity'                | :highest_severity                | nil
          'packager'                        | :package_manager                 | :first
          'package_manager'                 | :package_manager                 | :first
          'name'                            | :component_name                  | :first
          'component_name'                  | :component_name                  | :first
          'license'                         | :primary_license_spdx_identifier | :first
          'primary_license_spdx_identifier' | :primary_license_spdx_identifier | :first
        end

        with_them do
          it 'leads with the sort field and orders every source by the requested direction' do
            sort_terms = { field: field, order: :desc, missing_bucket: true }
            sort_terms[:missing_order] = missing_order if missing_order

            expect(sources).to eq(
              [
                { field => { terms: sort_terms } },
                { component_id: { terms: { field: :component_id, order: :desc, missing_bucket: false } } },
                { component_version_id: { terms: { field: :component_version_id, order: :desc,
                                                   missing_bucket: true, missing_order: :first } } }
              ]
            )
          end
        end
      end

      describe 'missing_order' do
        context 'when the source can hold a missing bucket' do
          let(:options) { super().merge(sort_by: 'packager', sort: sort) }

          where(:sort, :expected) do
            'asc'  | :last
            'desc' | :first
          end

          with_them do
            it 'places nulls where ::Sbom::AggregationsFinder places them' do
              expect(sources.first[:package_manager][:terms][:missing_order]).to eq(expected)
            end
          end
        end

        it 'is omitted for a source that cannot hold one' do
          component_id_source = sources.find { |source| source.key?(:component_id) }

          expect(component_id_source[:component_id][:terms]).not_to have_key(:missing_order)
        end
      end

      context 'when sort_by is a symbol' do
        let(:options) { super().merge(sort_by: :highest_severity) }

        it 'leads with the sort field' do
          expect(sources.first.keys).to eq([:highest_severity])
        end
      end

      describe 'sort direction' do
        where(:sort, :expected_order) do
          nil     | :asc
          'asc'   | :asc
          'desc'  | :desc
          'DESC'  | :desc
          :desc   | :desc
          'other' | :asc
        end

        with_them do
          let(:options) { super().merge(sort: sort) }

          it 'applies the direction to every source' do
            orders = sources.map { |source| source.each_value.first[:terms][:order] }

            expect(orders).to all(eq(expected_order))
          end
        end
      end
    end

    describe 'bucket size' do
      subject(:size) { by_component_and_version.dig(:aggs, :dependencies, :composite, :size) }

      where(:bucket_size, :expected_size) do
        nil   | 20
        10    | 10
        '10'  | 10
        100   | 100
        0     | 1
        -5    | 1
      end

      with_them do
        let(:options) { super().merge(bucket_size: bucket_size) }

        it 'returns the requested number of buckets' do
          expect(size).to eq(expected_size)
        end
      end
    end
  end

  describe '.by_version_counts' do
    subject(:by_version_counts) do
      described_class.by_version_counts(query_hash: query_hash, options: options)
    end

    let(:options) { { component_and_version_filters: { 'component1-version1' => [1, 10], 'component2' => [2, nil] } } }

    context 'when options[:component_and_version_filters] is not set' do
      let(:options) { {} }

      it 'does not modify the query_hash' do
        expect(by_version_counts).to eq(query_hash)
      end
    end

    it 'sets size to 0 so that no hits are returned' do
      expect(by_version_counts[:size]).to eq(0)
    end

    it 'keeps the name the caller gave each arm, so counts can be read back by name' do
      expect(by_version_counts.dig(:aggs, :version_counts, :filters)).to eq(
        filters: {
          'component1-version1' => {
            bool: { filter: [{ term: { component_id: 1 } }, { term: { component_version_id: 10 } }] }
          },
          'component2' => {
            bool: {
              filter: [
                { term: { component_id: 2 } },
                { bool: { must_not: { exists: { field: :component_version_id } } } }
              ]
            }
          }
        }
      )
    end

    it 'does not set a bucket size, so the arms cannot be truncated' do
      expect(by_version_counts.dig(:aggs, :version_counts)).not_to have_key(:composite)
      expect(by_version_counts.dig(:aggs, :version_counts, :filters)).not_to have_key(:size)
    end

    it 'aggregates the counts the dependency list shows' do
      expect(by_version_counts.dig(:aggs, :version_counts, :aggs)).to eq(
        occurrence_count: { cardinality: { field: :sbom_occurrence_id, precision_threshold: 3_000 } },
        project_count: { cardinality: { field: :project_id, precision_threshold: 3_000 } },
        vulnerability_count: { sum: { field: :vulnerability_count } }
      )
    end

    it 'counts distinct occurrences rather than relying on doc_count' do
      expect(by_version_counts.dig(:aggs, :version_counts, :aggs, :occurrence_count, :cardinality, :field))
        .to eq(:sbom_occurrence_id)
    end

    it 'does not partition by the sort field, so a dependency is never split across buckets' do
      arms = by_version_counts.dig(:aggs, :version_counts, :filters, :filters).values
      fields = arms.flat_map { |arm| arm.dig(:bool, :filter).flat_map { |c| c[:term]&.keys }.compact }

      expect(fields.uniq).to match_array(%i[component_id component_version_id])
    end

    it 'emits one arm per entry' do
      expect(by_version_counts.dig(:aggs, :version_counts, :filters, :filters).size).to eq(2)
    end
  end
end
