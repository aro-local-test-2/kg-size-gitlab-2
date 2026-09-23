# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::Ingestion::CompressedPackage::IngestionService, feature_category: :software_composition_analysis do
  describe '.execute' do
    subject(:execute) { described_class.execute(import_data) }

    describe 'transaction' do
      let(:import_data) { build_list(:pm_compressed_data_object, 10) }

      context 'when no errors' do
        it 'uses package metadata application record' do
          expect(PackageMetadata::ApplicationRecord).to receive(:transaction)
          execute
        end

        it 'adds new licenses' do
          expect { execute }
            .to change { PackageMetadata::License.all.size }.by(2)
            .and change { PackageMetadata::Package.all.size }.by(10)
        end

        it 'returns true so callers can tell the slice was persisted' do
          expect(execute).to be(true)
        end
      end

      context 'when error occurs' do
        it 'rolls back changes' do
          expect(PackageMetadata::Ingestion::CompressedPackage::PackageIngestionTask)
            .to receive(:execute).and_raise(StandardError)
          expect { execute }
          .to raise_error(StandardError)
          .and not_change(PackageMetadata::License, :count)
          .and not_change(PackageMetadata::Package, :count)
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

        it 'resolves each package to the row matching its declared role' do
          execute

          identifier_row = PackageMetadata::License.find_by(spdx_identifier: 'GPL-2.0+')
          expression_row = PackageMetadata::License.find_by(spdx_expression: 'GPL-2.0+')
          expect(identifier_row.id).not_to eq(expression_row.id)
          expect(PackageMetadata::Package.find_by(name: 'react').licenses[0]).to eq([identifier_row.id])
          expect(PackageMetadata::Package.find_by(name: 'vue').licenses[0]).to eq([expression_row.id])
        end
      end

      context 'with v3 records' do
        let(:records) { [record] }
        let(:record) do
          { 'name' => name, 'lowest_version' => '1.0.0', 'highest_version' => '9.9.9',
            'default_licenses' => default_licenses, 'other_licenses' => other_licenses }
        end

        let(:name) { 'chalk' }
        let(:default_licenses) { { 'licenses' => ['MIT'] } }
        let(:other_licenses) { [] }

        let(:sync_config) do
          build(:pm_sync_config, data_type: 'licenses', purl_type: 'npm', version_format: 'v3')
        end

        let(:data_file) do
          io = StringIO.new(records.map(&:to_json).join("\n"))
          Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0)
        end

        let(:import_data) do
          PackageMetadata::DataObjectFabricator.new(data_file: data_file, sync_config: sync_config).to_a
        end

        context 'when a record carries a blank license string alongside a valid one' do
          let(:default_licenses) { { 'licenses' => ['', 'MIT'] } }

          it 'still ingests the package with the valid license' do
            execute

            mit = PackageMetadata::License.find_by(spdx_identifier: 'MIT')
            package = PackageMetadata::Package.find_by(purl_type: 'npm', name: 'chalk')
            expect(package).to be_present
            expect(package.licenses[0]).to eq([mit.id])
          end
        end

        context 'when a license list contains a null entry' do
          let(:default_licenses) { { 'licenses' => [nil, 'MIT'] } }

          it 'drops the null value and keeps the package' do
            expect { execute }.not_to raise_error

            mit = PackageMetadata::License.find_by(spdx_identifier: 'MIT')
            package = PackageMetadata::Package.find_by(purl_type: 'npm', name: 'chalk')
            expect(package.licenses[0]).to eq([mit.id])
          end
        end

        context 'when a license list contains an integer entry' do
          let(:default_licenses) { { 'licenses' => [42, 'MIT'] } }

          it 'drops the integer value and keeps the package' do
            expect { execute }.not_to raise_error

            mit = PackageMetadata::License.find_by(spdx_identifier: 'MIT')
            package = PackageMetadata::Package.find_by(purl_type: 'npm', name: 'chalk')
            expect(package.licenses[0]).to eq([mit.id])
          end
        end

        context 'when a license value contains a NUL byte' do
          let(:default_licenses) { { 'licenses' => ["MIT\u0000", 'MIT'] } }

          it 'drops the value and keeps the package' do
            expect { execute }.not_to raise_error

            mit = PackageMetadata::License.find_by(spdx_identifier: 'MIT')
            package = PackageMetadata::Package.find_by(purl_type: 'npm', name: 'chalk')
            expect(package.licenses[0]).to eq([mit.id])
          end
        end

        context 'when one record carries an expression exceeding the column limit' do
          let(:records) do
            [
              record.merge('name' => 'express', 'default_licenses' => { 'expressions' => ['A' * 1025] }),
              record.merge('name' => 'vue', 'default_licenses' => { 'expressions' => ['MIT OR Apache-2.0'] })
            ]
          end

          it 'ingests the valid record without aborting the batch' do
            expect { execute }.not_to raise_error
            expect(PackageMetadata::License.find_by(spdx_expression: 'MIT OR Apache-2.0')).to be_present
          end
        end

        context 'when a record has no licenses at all' do
          let(:name) { 'lodash' }
          let(:default_licenses) { {} }

          it 'still ingests the package' do
            execute

            expect(PackageMetadata::Package.find_by(purl_type: 'npm', name: 'lodash')).to be_present
          end
        end

        context 'when a record carries more licenses than the schema admits' do
          let(:records) do
            [
              record.merge('name' => 'left-pad', 'default_licenses' => {
                'licenses' => (1..150).map { |i| "LIC-#{i}" },
                'expressions' => (1..51).map { |i| "EXPR-#{i} OR MIT" }
              }),
              record.merge('name' => 'vue')
            ]
          end

          it 'drops the oversized record before any rows are written and keeps the rest' do
            expect { execute }.not_to raise_error

            expect(PackageMetadata::Package.find_by(purl_type: 'npm', name: 'left-pad')).to be_nil
            expect(PackageMetadata::Package.find_by(purl_type: 'npm', name: 'vue')).to be_present
            expect(PackageMetadata::License.count).to eq(1)
          end
        end

        context 'when other_licenses carries expressions' do
          let(:name) { 'webpack' }
          let(:other_licenses) do
            [{ 'licenses' => [], 'expressions' => ['MIT OR Apache-2.0'], 'versions' => ['2.0.0'] }]
          end

          it 'references the expression row from the other-licenses section of the tuple' do
            execute

            expression = PackageMetadata::License.find_by(spdx_expression: 'MIT OR Apache-2.0')
            package = PackageMetadata::Package.find_by(purl_type: 'npm', name: 'webpack')
            expect(package.licenses[3]).to eq([[[expression.id], ['2.0.0']]])
          end
        end
      end

      context 'when import data contains both default and other licenses' do
        let(:import_data) do
          build_list(:pm_compressed_data_object, 1, name: 'requests', purl_type: 'pypi',
            default_licenses: ['Apache-1.0', 'Apache-2.0'],
            lowest_version: '2.3.0',
            highest_version: '2.31.0',
            other_licenses: [
              { "licenses" => ["ISC"], "versions" => ["0.10.2"] },
              { "licenses" => ["Apache-1.0"], "versions" => ["1.0.0"] },
              { "licenses" => ["unknown"], "versions" => ["0.13.2", "0.13.5"] },
              { "licenses" => ["MIT"], "versions" => ["0.0.1"] }
            ]
          )
        end

        let(:package) { PackageMetadata::Package.first }
        let(:license_ids) { PackageMetadata::License.all.pluck(:spdx_identifier, :id).to_h }
        let(:default_licenses) { package.licenses[0] }
        let(:lowest_version) { package.licenses[1] }
        let(:highest_version) { package.licenses[2] }
        let(:other_licenses) { package.licenses[3] }

        it 'adds the expected package and license data', :aggregate_failures do
          described_class.execute(import_data)
          expect(package.purl_type).to eq('pypi')
          expect(package.name).to eq('requests')
          expect(default_licenses)
            .to match_array([license_ids['Apache-1.0'], license_ids['Apache-2.0']])
          expect(lowest_version).to eq('2.3.0')
          expect(highest_version).to eq('2.31.0')
          expect(other_licenses)
            .to eq([
              [[license_ids['ISC']], ['0.10.2']],
              [[license_ids['Apache-1.0']], ['1.0.0']],
              [[license_ids['unknown']], ['0.13.2', '0.13.5']],
              [[license_ids['MIT']], ['0.0.1']]
            ])
        end
      end
    end
  end
end
