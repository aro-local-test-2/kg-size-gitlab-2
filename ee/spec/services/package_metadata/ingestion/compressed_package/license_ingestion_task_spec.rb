# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::Ingestion::CompressedPackage::LicenseIngestionTask, feature_category: :software_composition_analysis do
  describe '.execute' do
    context 'with SPDX identifier strings (v2 format)' do
      let(:import_data) do
        [
          build(:pm_compressed_data_object, purl_type: 'gem', name: 'rails',
            default_licenses: ['MIT'],
            other_licenses: [{ 'licenses' => %w[Apache APSL], 'versions' => ['v0.9.0', 'v0.9.1'] }]),
          build(:pm_compressed_data_object, purl_type: 'gem', name: 'activerecord',
            default_licenses: ['MIT'], other_licenses: [{ 'licenses' => ['GPL'], 'versions' => ['v0.1.0'] }]),
          build(:pm_compressed_data_object, purl_type: 'gem', name: '0mq', default_licenses: ['MIT-2'],
            other_licenses: []),
          build(:pm_compressed_data_object, purl_type: 'gem', name: 'redis', default_licenses: ['LGPL'],
            other_licenses: [])
        ]
      end

      let(:identifier_map) { { existing_license.spdx_identifier => existing_license.id } }
      let(:expression_map) { {} }

      let!(:existing_license) { create(:pm_license, spdx_identifier: 'MIT', spdx_expression: nil) }

      subject(:execute) { described_class.execute(import_data, identifier_map, expression_map) }

      it 'creates any data not in pm_licenses' do
        expect { execute }
          .to change { PackageMetadata::License.where.not(spdx_identifier: nil).pluck(:spdx_identifier).sort }
          .from(['MIT'])
          .to(%w[APSL Apache GPL LGPL MIT MIT-2])
      end

      it 'updates the identifier map with the ids of all newly inserted licenses' do
        execute
        expect(identifier_map).to eq(PackageMetadata::License.all.pluck(:spdx_identifier, :id).to_h)
      end
    end

    context 'with SPDX expression strings (v3 format)' do
      let(:import_data) do
        [
          PackageMetadata::PackageDataObjectV3.create(
            { 'name' => 'lodash',
              'default_licenses' => { 'licenses' => ['MIT'], 'expressions' => ['Apache-2.0 OR MIT'] },
              'other_licenses' => [{ 'licenses' => ['BSD-3-Clause'], 'expressions' => ['GPL-2.0-only OR MIT'],
                                     'versions' => ['1.0'] }] },
            'npm'
          )
        ]
      end

      let(:identifier_map) { {} }
      let(:expression_map) { {} }

      subject(:execute) { described_class.execute(import_data, identifier_map, expression_map) }

      it 'writes identifiers to spdx_identifier and expressions to spdx_expression' do
        execute
        expect(PackageMetadata::License.where.not(spdx_identifier: nil).pluck(:spdx_identifier))
          .to match_array(%w[MIT BSD-3-Clause])
        expressions = PackageMetadata::License.where.not(spdx_expression: nil).pluck(:spdx_expression)
        expect(expressions).to match_array(['Apache-2.0 OR MIT', 'GPL-2.0-only OR MIT'])
      end

      it 'adds identifiers and expressions to their own maps' do
        execute
        expect(identifier_map.keys).to include('MIT')
        expect(expression_map.keys).to include('Apache-2.0 OR MIT')
      end
    end

    context 'when a package reports both an identifier and an expression (different strings)' do
      let!(:existing_identifier) { create(:pm_license, spdx_identifier: 'MIT', spdx_expression: nil) }
      let!(:existing_expression) { create(:pm_license, spdx_identifier: nil, spdx_expression: 'MIT OR Apache-2.0') }

      let(:import_data) do
        [
          PackageMetadata::PackageDataObjectV3.create(
            { 'name' => 'express',
              'default_licenses' => { 'licenses' => ['MIT'], 'expressions' => ['MIT OR Apache-2.0'] } },
            'npm'
          )
        ]
      end

      let(:identifier_map) { {} }
      let(:expression_map) { {} }

      subject(:execute) { described_class.execute(import_data, identifier_map, expression_map) }

      it 'maps both to their existing rows without creating duplicates' do
        expect { execute }.not_to change { PackageMetadata::License.count }
        expect(identifier_map['MIT']).to eq(existing_identifier.id)
        expect(expression_map['MIT OR Apache-2.0']).to eq(existing_expression.id)
      end
    end

    context 'when the same string is declared as an identifier and as an expression' do
      let(:import_data) do
        [
          PackageMetadata::PackageDataObjectV3.create(
            { 'name' => 'react', 'default_licenses' => { 'licenses' => ['GPL-2.0+'] } }, 'npm'
          ),
          PackageMetadata::PackageDataObjectV3.create(
            { 'name' => 'vue', 'default_licenses' => { 'expressions' => ['GPL-2.0+'] } }, 'npm'
          )
        ]
      end

      let(:identifier_map) { {} }
      let(:expression_map) { {} }

      subject(:execute) { described_class.execute(import_data, identifier_map, expression_map) }

      it 'creates one row per role and maps each string within its own role' do
        expect { execute }.to change { PackageMetadata::License.count }.by(2)

        identifier_row = PackageMetadata::License.find_by(spdx_identifier: 'GPL-2.0+')
        expression_row = PackageMetadata::License.find_by(spdx_expression: 'GPL-2.0+')
        expect(identifier_row.id).not_to eq(expression_row.id)
        expect(identifier_map['GPL-2.0+']).to eq(identifier_row.id)
        expect(expression_map['GPL-2.0+']).to eq(expression_row.id)
      end

      context 'when the identifier row already exists' do
        let!(:existing_identifier) { create(:pm_license, spdx_identifier: 'GPL-2.0+', spdx_expression: nil) }

        it 'still creates and maps the expression row' do
          expect { execute }.to change { PackageMetadata::License.count }.by(1)

          expect(identifier_map['GPL-2.0+']).to eq(existing_identifier.id)
          expect(expression_map['GPL-2.0+'])
            .to eq(PackageMetadata::License.find_by(spdx_expression: 'GPL-2.0+').id)
        end
      end
    end

    context 'with blank license values' do
      let(:identifier_map) { {} }
      let(:expression_map) { {} }

      subject(:execute) { described_class.execute(import_data, identifier_map, expression_map) }

      context 'when a v3 object contains blank identifiers' do
        let(:import_data) do
          [
            PackageMetadata::PackageDataObjectV3.create(
              { 'name' => 'chalk', 'default_licenses' => { 'licenses' => ['', 'MIT'], 'expressions' => [] } },
              'npm'
            )
          ]
        end

        it 'silently skips blank spdx_identifier values' do
          expect(Gitlab::AppJsonLogger).not_to receive(:warn)
          execute
          expect(PackageMetadata::License.pluck(:spdx_identifier).compact).to eq(['MIT'])
        end
      end

      context 'when a v3 object contains blank expressions' do
        let(:import_data) do
          [
            PackageMetadata::PackageDataObjectV3.create(
              { 'name' => 'commander', 'default_licenses' => { 'expressions' => ['', 'MIT OR Apache-2.0'] } },
              'pypi'
            )
          ]
        end

        it 'silently skips blank spdx_expression values' do
          expect(Gitlab::AppJsonLogger).not_to receive(:warn)
          execute
          expect(PackageMetadata::License.pluck(:spdx_expression).compact).to eq(['MIT OR Apache-2.0'])
        end
      end

      context 'when no blank values are present' do
        let(:import_data) do
          [
            PackageMetadata::PackageDataObjectV3.create(
              { 'name' => 'axios',
                'default_licenses' => { 'licenses' => ['MIT'] },
                'other_licenses' => [{ 'licenses' => ['Apache-2.0'], 'expressions' => ['MIT OR Apache-2.0'],
                                       'versions' => ['1.0'] }] },
              'npm'
            )
          ]
        end

        it 'does not log a warning' do
          expect(Gitlab::AppJsonLogger).not_to receive(:warn)
          execute
        end
      end
    end
  end
end
