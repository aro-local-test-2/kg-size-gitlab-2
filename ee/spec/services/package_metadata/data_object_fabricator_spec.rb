# frozen_string_literal: true

require 'spec_helper'

require 'csv'

RSpec.describe PackageMetadata::DataObjectFabricator, feature_category: :software_composition_analysis do
  describe 'enumerable' do
    subject(:data_objects) { described_class.new(data_file: data_file, sync_config: sync_config).to_a }

    shared_examples_for 'it handles errors' do
      it 'tracks the error with sync config context' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(ArgumentError), hash_including(
            message: 'Skipped malformed package metadata record',
            data_type: sync_config.data_type,
            purl_type: sync_config.purl_type))
          .once
        subject
      end

      it 'does not re-raise the error' do
        expect { subject }.not_to raise_error
      end
    end

    context 'when licenses' do
      let(:sync_config) do
        build(:pm_sync_config, data_type: 'licenses', purl_type: 'maven', version_format: version_format)
      end

      context 'and data_file is csv' do
        let(:version_format) { 'v1' }
        let(:io) { File.open(Rails.root.join('ee/spec/fixtures/package_metadata/sync/licenses/v1/maven.csv')) }
        let(:data_file) { Gitlab::PackageMetadata::Connector::CsvDataFile.new(io, 0, 0) }

        it do
          is_expected.to match_array([
            have_attributes(purl_type: sync_config.purl_type, name: 'ai.benshi.android.sdk/core',
              version: '0.1.0-alpha01', license: 'Apache-2.0'),
            have_attributes(purl_type: sync_config.purl_type, name: 'ai.benshi.android.sdk/core',
              version: '1.2.0-rc01', license: 'Apache-2.0'),
            have_attributes(purl_type: sync_config.purl_type, name: 'xpp3/xpp3', version: '1.1.4c', license: 'unknown'),
            have_attributes(purl_type: sync_config.purl_type, name: 'xpp3/xpp3', version: '1.1.4c',
              license: 'Apache-1.1'),
            have_attributes(purl_type: sync_config.purl_type, name: 'xpp3/xpp3', version: '1.1.4c', license: 'CC-PDDC'),
            have_attributes(purl_type: sync_config.purl_type, name: 'xml-apis/xml-apis', version: '1.3.04',
              license: 'unknown'),
            have_attributes(purl_type: sync_config.purl_type, name: 'xml-apis/xml-apis', version: '2.0.2',
              license: 'unknown'),
            have_attributes(purl_type: sync_config.purl_type, name: 'uk.org.retep.tools.maven/script', version: '10.1',
              license: '0BSD')
          ])
        end
      end

      context 'and data_file is ndjson' do
        let(:version_format) { 'v2' }
        let(:io) { File.open(Rails.root.join('ee/spec/fixtures/package_metadata/sync/licenses/v2/maven.ndjson')) }
        let(:data_file) { Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0) }

        it do
          is_expected.to match_array([
            have_attributes(purl_type: sync_config.purl_type, name: "ai.benshi.android.sdk/core",
              lowest_version: "0.1.0-alpha01", other_licenses: [], highest_version: "1.2.0-rc01",
              default_licenses: ["Apache-2.0"]),
            have_attributes(purl_type: sync_config.purl_type, name: "xpp3/xpp3", lowest_version: "1.1.4c",
              other_licenses: [{ "licenses" => ["unknown"], "versions" => ["1.1.2a", "1.1.2a_min", "1.1.3.3",
                "1.1.3.3_min", "1.1.3.4.O", "1.1.3.4-RC3", "1.1.3.4-RC8"] }], highest_version: "1.1.4c",
              default_licenses: ["unknown", "Apache-1.1", "CC-PDDC"]),
            have_attributes(purl_type: sync_config.purl_type, name: "xml-apis/xml-apis", lowest_version: "2.0.0",
              other_licenses: [{ "licenses" => ["Apache-2.0"], "versions" => ["1.3.04", "1.0.b2", "1.3.03"] },
                { "licenses" => ["Apache-2.0", "SAX-PD", "W3C-20150513"], "versions" => ["1.4.01"] }],
              highest_version: "2.0.2", default_licenses: ["unknown"]),
            have_attributes(purl_type: sync_config.purl_type, name: "uk.org.retep.tools.maven/script",
              lowest_version: "10.1",
              other_licenses: [], highest_version: "9.8-RC1", default_licenses: ["0BSD", "Apache-1.1", "Apache-2.0",
                "BSD-2-Clause", "CC-PDDC"])
          ])
        end

        it_behaves_like 'it handles errors'
      end

      context 'and data_file is v3 ndjson' do
        let(:version_format) { 'v3' }
        let(:data_file) do
          Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(StringIO.new("#{record.to_json}\n"), 0, 0)
        end

        context 'with coexistence of licenses and expressions in default_licenses' do
          let(:record) do
            { 'name' => 'lodash', 'lowest_version' => '0.2.0', 'highest_version' => '1.1.9',
              'default_licenses' => { 'licenses' => ['GPL-3.0'], 'expressions' => ['GPL-3.0+'] },
              'other_licenses' => [{ 'licenses' => ['BSD-3-Clause'], 'expressions' => ['BSD-3-Clause OR MIT'],
                                     'versions' => ['2.0'] }] }
          end

          it 'returns both identifier and expression' do
            is_expected.to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                purl_type: sync_config.purl_type, name: 'lodash',
                lowest_version: '0.2.0', highest_version: '1.1.9',
                default_identifiers: ['GPL-3.0'], default_expressions: ['GPL-3.0+'],
                other_licenses: [{ 'licenses' => ['BSD-3-Clause'], 'expressions' => ['BSD-3-Clause OR MIT'],
                                   'versions' => ['2.0'] }]
              ))
            )
          end
        end

        context 'with expression-only default_licenses' do
          let(:record) do
            { 'name' => 'express', 'lowest_version' => '2.5.8', 'highest_version' => '2.9.8',
              'default_licenses' => { 'expressions' => ['MIT OR Apache-2.0'] },
              'other_licenses' => [{ 'expressions' => ['GPL-2.0-only OR MIT'], 'versions' => ['1.5'] }] }
          end

          it 'returns the expression' do
            is_expected.to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                purl_type: sync_config.purl_type, name: 'express',
                lowest_version: '2.5.8', highest_version: '2.9.8',
                default_identifiers: [], default_expressions: ['MIT OR Apache-2.0'],
                other_licenses: [{ 'licenses' => [], 'expressions' => ['GPL-2.0-only OR MIT'],
                                   'versions' => ['1.5'] }]
              ))
            )
          end
        end

        context 'with only identifiers and no expressions key' do
          let(:record) do
            { 'name' => 'react', 'lowest_version' => '0.1.0', 'highest_version' => '0.1.1',
              'default_licenses' => { 'licenses' => ['MIT'] },
              'other_licenses' => [{ 'licenses' => ['Apache-2.0'], 'versions' => ['1.0'] }] }
          end

          it 'returns an object with only identifiers' do
            is_expected.to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                spdx_identifiers: match_array(['MIT', 'Apache-2.0']),
                spdx_expressions: []
              ))
            )
          end
        end

        context 'with expressions in other_licenses' do
          let(:record) do
            { 'name' => 'webpack', 'lowest_version' => '0.1.0', 'highest_version' => '0.6.3',
              'default_licenses' => { 'licenses' => ['LGPL-2.0-or-later'] },
              'other_licenses' => [{ 'licenses' => ['LGPL-2.1'], 'expressions' => ['LGPL-2.1+'],
                                     'versions' => ['1.0'] }] }
          end

          it 'keeps other_licenses expressions separate from identifiers' do
            is_expected.to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                purl_type: sync_config.purl_type, name: 'webpack',
                lowest_version: '0.1.0', highest_version: '0.6.3',
                default_identifiers: ['LGPL-2.0-or-later'], default_expressions: [],
                other_licenses: [{ 'licenses' => ['LGPL-2.1'], 'expressions' => ['LGPL-2.1+'],
                                   'versions' => ['1.0'] }]
              ))
            )
          end
        end

        context 'with a record that is not a JSON object' do
          let(:data_file) do
            io = StringIO.new("42\n#{record.to_json}\n")
            Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0)
          end

          let(:record) do
            { 'name' => 'react', 'default_licenses' => { 'licenses' => ['MIT'] } }
          end

          it 'drops the malformed record through error tracking and keeps the valid one' do
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(kind_of(ArgumentError), hash_including(data: 42)).once

            expect(data_objects).to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(name: 'react'))
            )
          end
        end

        context 'when records carry unusable license values' do
          let(:records) do
            [
              { 'name' => 'chalk',
                'default_licenses' => {
                  'licenses' => [nil, 42, '', "MIT\u0000", 'A' * 51, 'A' * 50],
                  'expressions' => ['A' * 1025, 'A' * 1024]
                } },
              { 'name' => 'commander', 'default_licenses' => { 'licenses' => [''] } }
            ]
          end

          let(:data_file) do
            io = StringIO.new(records.map(&:to_json).join("\n"))
            Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0)
          end

          it 'silently filters them and keeps values at the length boundaries' do
            expect(Gitlab::AppJsonLogger).not_to receive(:warn)
            expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

            expect(data_objects).to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                name: 'chalk',
                spdx_identifiers: ['A' * 50],
                spdx_expressions: ['A' * 1024]
              )),
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                name: 'commander',
                spdx_identifiers: [],
                spdx_expressions: []
              ))
            )
          end
        end

        context 'when a record exceeds the license set cap' do
          let(:oversized) do
            { 'name' => 'left-pad', 'default_licenses' => {
              'licenses' => (1..150).map { |i| "LIC-#{i}" },
              'expressions' => (1..51).map { |i| "EXPR-#{i} OR MIT" }
            } }
          end

          let(:at_cap) do
            { 'name' => 'chalk', 'default_licenses' => {
              'licenses' => (1..150).map { |i| "LIC-#{i}" } + ['', nil],
              'expressions' => (1..50).map { |i| "EXPR-#{i} OR MIT" }
            } }
          end

          let(:data_file) do
            io = StringIO.new([oversized, at_cap].map(&:to_json).join("\n"))
            Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0)
          end

          it 'drops the oversized record through error tracking and keeps the record at the cap' do
            expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(kind_of(ArgumentError), kind_of(Hash)).once

            expect(data_objects).to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(name: 'chalk'))
            )
          end
        end

        context 'with null name' do
          let(:record) { { 'name' => nil, 'default_licenses' => {} } }

          it_behaves_like 'it handles errors'
        end

        context 'with default_licenses entirely absent' do
          let(:record) { { 'name' => 'chalk', 'lowest_version' => '0.0.3', 'highest_version' => '0.11.0' } }

          it 'returns an object with no identifiers or expressions' do
            is_expected.to contain_exactly(
              be_a(PackageMetadata::PackageDataObjectV3).and(have_attributes(
                spdx_identifiers: [],
                spdx_expressions: []
              ))
            )
          end
        end
      end
    end

    context 'when advisories' do
      let(:sync_config) { build(:pm_sync_config, data_type: 'advisories', purl_type: 'maven') }
      let(:io) { File.open(Rails.root.join('ee/spec/fixtures/package_metadata/sync/advisories/v2/maven.ndjson')) }
      let(:data_file) { Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0) }

      subject(:data_objects) { described_class.new(data_file: data_file, sync_config: sync_config).to_a }

      it do
        is_expected.to match_array([have_attributes(advisory_xid: 'd4f176d6-0a07-46f4-9da5-22df92e5efa0',
          source_xid: 'glad', title: "Incorrect Permission Assignment for Critical Resource",
          description: "A missing permission check in Jenkins Google Kubernetes Engine Plugin allows attackers " \
                       "with Overall/Read permission to obtain limited information about the scope of a credential " \
                       "with an attacker-specified credentials ID.",
          cvss_v2: "AV:N/AC:L/Au:S/C:P/I:N/A:N",
          cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N",
          cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N",
          published_date: "2019-10-16",
          urls: ["https://nvd.nist.gov/vuln/detail/CVE-2019-10445",
            "https://jenkins.io/security/advisory/2019-10-16/#SECURITY-1607"])])
      end

      it_behaves_like 'it handles errors'
    end

    context 'when cve enrichment' do
      let(:sync_config) { build(:pm_sync_config, data_type: 'cve_enrichment', version_format: 'v2') }
      let(:io) { File.open(Rails.root.join('ee/spec/fixtures/package_metadata/sync/cve_enrichment/v2/data.ndjson')) }
      let(:data_file) { Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(io, 0, 0) }

      subject(:data_objects) { described_class.new(data_file: data_file, sync_config: sync_config).to_a }

      it do
        is_expected.to match_array([
          have_attributes(cve_id: 'CVE-2020-1234', epss_score: 0.5, is_known_exploit: false),
          have_attributes(cve_id: 'CVE-2021-12345', epss_score: 0.6, is_known_exploit: true),
          have_attributes(cve_id: 'CVE-2022-12345', epss_score: 0.4, is_known_exploit: false)
        ])
      end

      it_behaves_like 'it handles errors'
    end
  end
end
