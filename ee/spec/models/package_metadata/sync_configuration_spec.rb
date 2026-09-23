# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::SyncConfiguration, feature_category: :software_composition_analysis do
  using RSpec::Parameterized::TableSyntax

  before do
    allow(File).to receive(:exist?).and_return(false)
  end

  describe 'configs based on enabled purl types' do
    let(:all_purl_types) { Enums::Sbom.purl_types.values }

    shared_examples_for 'it returns all enabled sync configs' do
      let(:purl_type_map) { Enums::Sbom.purl_types_numerical }

      before do
        stub_application_setting(package_metadata_purl_types: enabled_purl_types)
      end

      specify do
        expected = expected_purl_types.map do |purl_type|
          have_attributes(data_type: expected_data_type, storage_type: expected_storage_type,
            base_uri: expected_base_uri, version_format: expected_version_format,
            purl_type: purl_type_map[purl_type])
        end

        expect(configurations).to match_array(expected)
      end
    end

    context 'when syncing licenses' do
      let(:expected_data_type) { 'licenses' }
      let(:expected_storage_type) { :pds }
      let(:expected_base_uri) { described_class::Location::PDS_LICENSES_STAGING_ENDPOINT }
      let(:expected_version_format) { 'v3' }

      subject(:configurations) { described_class.configs_for('licenses') }

      where(:enabled_purl_types, :expected_purl_types) do
        ref(:all_purl_types)  | ref(:all_purl_types)
        [1, 5]                | [1, 5]
        []                    | []
      end

      with_them do
        it_behaves_like 'it returns all enabled sync configs'
      end

      # A v2 checkpoint stores a GCS export timestamp, which means nothing to PDS.
      # Pinning v3 forces a fresh row so the first PDS call is /all, not /delta.
      it 'resolves a fresh checkpoint rather than reusing the v2 row', :aggregate_failures do
        stub_application_setting(package_metadata_purl_types: [1])
        v2_checkpoint = create(:pm_checkpoint, data_type: 'licenses', version_format: 'v2',
          purl_type: 'composer', sequence: 1_700_000_000, chunk: 7)

        config = described_class.configs_for('licenses').first
        checkpoint = PackageMetadata::Checkpoint
          .with_path_components(config.data_type, config.version_format, config.purl_type)

        expect(checkpoint).to be_new_record
        expect(checkpoint).to have_attributes(version_format: 'v3', sequence: nil, chunk: nil)
        expect(checkpoint).to be_first_sync
        expect(v2_checkpoint.reload).to have_attributes(sequence: 1_700_000_000, chunk: 7)
      end

      # These two do not use `with_them`: a nested group does not inherit the
      # parent's `where`, so it would silently produce no examples at all.
      # The purl-type matrix above is not what they are about anyway.
      context 'when licenses are vendored for an air-gapped install' do
        before do
          stub_application_setting(package_metadata_purl_types: [1])
          allow(File).to receive(:exist?)
            .with(described_class::Location::LICENSES_PATH).and_return(true)
        end

        # The flag is on here, so this pins the fallback: no v3 directory on disk
        # means the instance keeps syncing the v2 layout it does have.
        it 'returns offline v2 configs', :aggregate_failures do
          expect(configurations.size).to eq(1)
          expect(configurations).to all(
            have_attributes(storage_type: :offline, version_format: 'v2',
              base_uri: described_class::Location::LICENSES_PATH)
          )
        end

        context 'when a v3 directory is vendored' do
          before do
            allow(File).to receive(:exist?)
              .with(File.join(described_class::Location::LICENSES_PATH, 'v3')).and_return(true)
          end

          it 'returns offline v3 configs', :aggregate_failures do
            expect(configurations.size).to eq(1)
            expect(configurations).to all(
              have_attributes(storage_type: :offline, version_format: 'v3',
                base_uri: described_class::Location::LICENSES_PATH)
            )
          end
        end
      end

      context 'when the v3 rollout flag is disabled' do
        before do
          stub_application_setting(package_metadata_purl_types: [1])
          stub_feature_flags(sync_v3_license_expressions: false)
        end

        it 'returns GCS v2 configs', :aggregate_failures do
          expect(configurations.size).to eq(1)
          expect(configurations).to all(
            have_attributes(storage_type: :gcp, version_format: 'v2',
              base_uri: described_class::Location::LICENSES_BUCKET)
          )
        end
      end
    end

    context 'when syncing advisories' do
      let(:expected_data_type) { 'advisories' }
      let(:expected_storage_type) { :gcp }
      let(:expected_base_uri) { described_class::Location::ADVISORIES_BUCKET }
      let(:expected_version_format) { 'v2' }

      subject(:configurations) { described_class.configs_for('advisories') }

      where(:enabled_purl_types, :expected_purl_types) do
        ref(:all_purl_types)  | ref(:all_purl_types)
        [1, 5]                | [1, 5]
        []                    | []
      end

      with_them do
        it_behaves_like 'it returns all enabled sync configs'
      end
    end
  end

  context 'when syncing malware advisories' do
    before do
      stub_application_setting(package_metadata_purl_types: [1, 5])
    end

    subject(:configurations) { described_class.configs_for('malware_advisories') }

    it 'returns a v3 PDS sync config per enabled purl type', :aggregate_failures do
      expect(configurations.size).to eq(2)
      expect(configurations).to all(
        have_attributes(data_type: 'malware_advisories', storage_type: :pds, version_format: 'v3',
          base_uri: described_class::Location::PDS_MALWARE_STAGING_ENDPOINT)
      )
    end
  end

  context 'when syncing an unsupported data type' do
    subject(:configurations!) { described_class.configs_for('foo') }

    specify do
      expect { configurations! }.to raise_error(ArgumentError)
    end
  end

  describe PackageMetadata::SyncConfiguration::Location do
    # Callers supply :production_endpoint and :staging_endpoint.
    shared_examples_for 'a PDS endpoint' do
      where(:rails_env, :staging, :expected_endpoint) do
        'production'  | false | ref(:production_endpoint)
        'production'  | true  | ref(:staging_endpoint)
        'development' | false | ref(:staging_endpoint)
        'test'        | false | ref(:staging_endpoint)
        'review'      | false | ref(:staging_endpoint)
      end

      with_them do
        before do
          stub_rails_env(rails_env)
          allow(Gitlab).to receive(:staging?).and_return(staging)
        end

        it { is_expected.to eq(expected_endpoint) }
      end
    end

    describe '.for_licenses' do
      subject { described_class.for_licenses }

      # A vendored directory wins in both flag states; the flag only picks between
      # the two online destinations.
      where(:v3_flag, :filepath_exists, :old_filepath_exists, :expected_storage_type, :expected_base_uri) do
        true     | true      | false   | :offline  | described_class::LICENSES_PATH
        true     | false     | true    | :offline  | described_class::OLD_LICENSES_PATH
        true     | true      | true    | :offline  | described_class::LICENSES_PATH
        true     | false     | false   | :pds      | described_class::PDS_LICENSES_ENDPOINT
        false    | true      | false   | :offline  | described_class::LICENSES_PATH
        false    | false     | true    | :offline  | described_class::OLD_LICENSES_PATH
        false    | true      | true    | :offline  | described_class::LICENSES_PATH
        false    | false     | false   | :gcp      | described_class::LICENSES_BUCKET
      end

      with_them do
        before do
          stub_feature_flags(sync_v3_license_expressions: v3_flag)
          stub_rails_env('production')
          allow(Gitlab).to receive(:staging?).and_return(false)
          allow(File).to receive(:exist?).with(described_class::LICENSES_PATH)
            .and_return(filepath_exists)
          allow(File).to receive(:exist?).with(described_class::OLD_LICENSES_PATH)
            .and_return(old_filepath_exists)
        end

        it { is_expected.to eq([expected_storage_type, expected_base_uri]) }
      end
    end

    describe '.licenses_version_format' do
      subject { described_class.licenses_version_format(storage_type, described_class::LICENSES_PATH) }

      # The flag decides, except that an offline root without a v3 directory falls
      # back to v2, so a v2-only instance keeps syncing v2.
      where(:storage_type, :v3_flag, :v3_vendored, :expected_version_format) do
        :pds     | true   | false  | 'v3'
        :offline | true   | true   | 'v3'
        :offline | true   | false  | 'v2'
        :offline | false  | true   | 'v2'
        :gcp     | false  | false  | 'v2'
      end

      with_them do
        let(:v3_path) { File.join(described_class::LICENSES_PATH, 'v3') }

        before do
          stub_feature_flags(sync_v3_license_expressions: v3_flag)
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(v3_path).and_return(v3_vendored)
        end

        it { is_expected.to eq(expected_version_format) }
      end
    end

    describe '.licenses_pds_endpoint' do
      subject { described_class.licenses_pds_endpoint }

      let(:production_endpoint) { described_class::PDS_LICENSES_ENDPOINT }
      let(:staging_endpoint) { described_class::PDS_LICENSES_STAGING_ENDPOINT }

      it_behaves_like 'a PDS endpoint'
    end

    describe '.for_advisories' do
      subject { described_class.for_advisories }

      where(:filepath_exists, :expected_storage_type, :expected_base_uri) do
        true     | :offline  | described_class::ADVISORIES_PATH
        false    | :gcp      | described_class::ADVISORIES_BUCKET
      end

      with_them do
        before do
          allow(File).to receive(:exist?).with(described_class::ADVISORIES_PATH)
            .and_return(filepath_exists)
        end

        it { is_expected.to match_array([expected_storage_type, expected_base_uri]) }
      end
    end

    describe '.for_cve_enrichment' do
      subject { described_class.for_cve_enrichment }

      where(:filepath_exists, :expected_storage_type, :expected_base_uri) do
        true     | :offline  | described_class::CVE_ENRICHMENT_PATH
        false    | :gcp      | described_class::CVE_ENRICHMENT_BUCKET
      end

      with_them do
        before do
          allow(File).to receive(:exist?).with(described_class::CVE_ENRICHMENT_PATH)
            .and_return(filepath_exists)
        end

        it { is_expected.to match_array([expected_storage_type, expected_base_uri]) }
      end
    end

    describe '.for_malware_advisories' do
      subject { described_class.for_malware_advisories }

      context 'when the vendor path exists (air-gapped)' do
        before do
          allow(File).to receive(:exist?).with(described_class::MALWARE_ADVISORIES_PATH).and_return(true)
        end

        it { is_expected.to eq([:offline, described_class::MALWARE_ADVISORIES_PATH]) }
      end

      context 'when the vendor path is absent (online PDS)' do
        before do
          allow(File).to receive(:exist?).with(described_class::MALWARE_ADVISORIES_PATH).and_return(false)
          allow(described_class).to receive(:malware_pds_endpoint).and_return('https://pds.example.com/malware')
        end

        it { is_expected.to eq([:pds, 'https://pds.example.com/malware']) }
      end
    end

    describe '.malware_pds_endpoint' do
      subject { described_class.malware_pds_endpoint }

      let(:production_endpoint) { described_class::PDS_MALWARE_ENDPOINT }
      let(:staging_endpoint) { described_class::PDS_MALWARE_STAGING_ENDPOINT }

      it_behaves_like 'a PDS endpoint'
    end
  end

  describe '.registry' do
    ::Enums::Sbom::PURL_TYPES.each do |purl_type, _|
      context "when purl type is #{purl_type}" do
        it "returns a non-default value" do
          expect(described_class.registry_id(purl_type)).not_to be_nil
        end
      end
    end
  end

  describe '#to_s' do
    subject { described_class.new('advisories', 'gcp', 'adv-bucket', 'v1', 'pypi').to_s }

    it { is_expected.to eq('advisories:gcp/adv-bucket/v1/pypi') }
  end
end
