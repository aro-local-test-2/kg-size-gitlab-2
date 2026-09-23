# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::SbomOccurrenceRefFilters, feature_category: :dependency_management do
  include_context 'with filters shared context'

  describe '.by_component_ids' do
    subject(:by_component_ids) { described_class.by_component_ids(query_hash: query_hash, options: options) }

    context 'when options[:component_ids] is empty' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:component_ids] is provided' do
      let(:options) { { component_ids: [1, 2] } }
      let(:expected_filter) do
        [{ terms: { _name: 'filters:component_ids', component_id: [1, 2] } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_component_names' do
    subject(:by_component_names) { described_class.by_component_names(query_hash: query_hash, options: options) }

    context 'when options[:component_names] is empty' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:component_names] is provided' do
      let(:options) { { component_names: %w[express] } }
      let(:expected_filter) do
        [{ terms: { _name: 'filters:component_names', component_name: %w[express] } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_package_managers' do
    subject(:by_package_managers) { described_class.by_package_managers(query_hash: query_hash, options: options) }

    context 'when options[:package_managers] is empty' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:package_managers] is provided' do
      let(:options) { { package_managers: %w[npm yarn] } }
      let(:expected_filter) do
        [{ terms: { _name: 'filters:package_managers', package_manager: %w[npm yarn] } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_component_versions' do
    subject(:by_component_versions) do
      described_class.by_component_versions(query_hash: query_hash, options: options)
    end

    context 'when neither option is provided' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:component_versions] is provided' do
      let(:options) { { component_versions: %w[1.0.0] } }
      let(:expected_filter) do
        [{ terms: { _name: 'filters:component_versions', component_version: %w[1.0.0] } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when options[:not_component_versions] is provided' do
      let(:options) { { not_component_versions: %w[1.0.0] } }

      it 'adds the filter to must_not' do
        query_hash = by_component_versions
        expected_must_not = [{ terms: { _name: 'filters:not_component_versions', component_version: %w[1.0.0] } }]

        aggregate_failures do
          expect(query_hash.dig(:query, :bool, :must_not)).to eq(expected_must_not)
          expect(query_hash.dig(:query, :bool, :filter)).to be_empty
          expect(query_hash.dig(:query, :bool, :must)).to be_empty
          expect(query_hash.dig(:query, :bool, :should)).to be_empty
        end
      end
    end

    context 'when both options are provided' do
      let(:options) { { component_versions: %w[1.0.0], not_component_versions: %w[2.0.0] } }

      it 'adds both filters' do
        query_hash = by_component_versions

        aggregate_failures do
          expect(query_hash.dig(:query, :bool, :filter)).to eq(
            [{ terms: { _name: 'filters:component_versions', component_version: %w[1.0.0] } }]
          )
          expect(query_hash.dig(:query, :bool, :must_not)).to eq(
            [{ terms: { _name: 'filters:not_component_versions', component_version: %w[2.0.0] } }]
          )
        end
      end
    end
  end

  describe '.by_licenses' do
    subject(:by_licenses) { described_class.by_licenses(query_hash: query_hash, options: options) }

    context 'when options[:licenses] is empty' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:licenses] is provided without a depth' do
      let(:options) { { licenses: %w[MIT] } }
      let(:expected_filter) do
        [{ terms: { _name: 'filters:licenses', primary_license_spdx_identifier: %w[MIT] } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when options[:include_secondary_license] is set' do
      let(:options) { { licenses: %w[MIT], include_secondary_license: true } }
      let(:expected_filter) do
        [{
          bool: {
            _name: 'filters:licenses',
            should: [
              { terms: { primary_license_spdx_identifier: %w[MIT] } },
              { terms: { secondary_license_spdx_identifier: %w[MIT] } }
            ],
            minimum_should_match: 1
          }
        }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_project_ids' do
    subject(:by_project_ids) { described_class.by_project_ids(query_hash: query_hash, options: options) }

    context 'when options[:project_ids] is empty' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:project_ids] is provided' do
      let(:options) { { project_ids: [7] } }
      let(:expected_filter) do
        [{ terms: { _name: 'filters:project_ids', project_id: [7] } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_source_types' do
    subject(:by_source_types) { described_class.by_source_types(query_hash: query_hash, options: options) }

    let(:missing_source) { { bool: { must_not: { exists: { field: :source_type } } } } }

    context 'when options[:source_types] is not provided' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:source_types] is an empty array' do
      let(:options) { { source_types: [] } }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when only enum values are provided' do
      let(:options) { { source_types: [0, 1] } }
      let(:expected_filter) do
        [{
          bool: {
            _name: 'filters:source_types',
            should: [{ terms: { source_type: [0, 1] } }],
            minimum_should_match: 1
          }
        }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when only the nil source is provided' do
      let(:options) { { source_types: [nil] } }
      let(:expected_filter) do
        [{
          bool: {
            _name: 'filters:source_types',
            should: [missing_source],
            minimum_should_match: 1
          }
        }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when both enum values and the nil source are provided' do
      let(:options) { { source_types: [0, 1, nil] } }
      let(:expected_filter) do
        [{
          bool: {
            _name: 'filters:source_types',
            should: [{ terms: { source_type: [0, 1] } }, missing_source],
            minimum_should_match: 1
          }
        }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_malware' do
    subject(:by_malware) { described_class.by_malware(query_hash: query_hash, options: options) }

    context 'when options[:malware] is not provided' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:malware] is not a boolean' do
      let(:options) { { malware: 'true' } }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:malware] is true' do
      let(:options) { { malware: true } }
      let(:expected_filter) do
        [{ term: { malware: { _name: 'filters:malware', value: true } } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when options[:malware] is false' do
      let(:options) { { malware: false } }
      let(:expected_filter) do
        [{ term: { malware: { _name: 'filters:malware', value: false } } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_security_project_tracked_context_id' do
    subject(:by_security_project_tracked_context_id) do
      described_class.by_security_project_tracked_context_id(query_hash: query_hash, options: options)
    end

    context 'when options[:security_project_tracked_context_id] is empty' do
      let(:options) { {} }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:security_project_tracked_context_id] is provided' do
      let(:options) { { security_project_tracked_context_id: 1 } }
      let(:expected_filter) do
        [{
          terms: {
            _name: 'filters:security_project_tracked_context_id',
            security_project_tracked_context_id: [1]
          }
        }]
      end

      it_behaves_like 'adds filter to query_hash'
    end
  end

  describe '.by_tracked_refs_scope' do
    subject(:by_tracked_refs_scope) { described_class.by_tracked_refs_scope(query_hash: query_hash, options: options) }

    context 'when no options are provided' do
      let(:options) { {} }
      let(:expected_filter) do
        [{ term: { is_default: { _name: 'filters:is_default', value: true } } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when options[:tracked_refs_scope] is :default_branches' do
      let(:options) { { tracked_refs_scope: :default_branches } }
      let(:expected_filter) do
        [{ term: { is_default: { _name: 'filters:is_default', value: true } } }]
      end

      it_behaves_like 'adds filter to query_hash'
    end

    context 'when options[:tracked_refs_scope] is :all_refs' do
      let(:options) { { tracked_refs_scope: :all_refs } }

      it_behaves_like 'does not modify the query_hash'
    end

    context 'when options[:security_project_tracked_context_id] is provided' do
      let(:options) { { security_project_tracked_context_id: 1 } }

      it_behaves_like 'does not modify the query_hash'
    end
  end

  describe '.by_is_default' do
    subject(:by_is_default) { described_class.by_is_default(query_hash: query_hash, value: false) }

    let(:expected_filter) do
      [{ term: { is_default: { _name: 'filters:is_default', value: false } } }]
    end

    it_behaves_like 'adds filter to query_hash'
  end
end
