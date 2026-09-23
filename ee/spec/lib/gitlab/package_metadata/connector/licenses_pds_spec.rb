# frozen_string_literal: true

require 'spec_helper'

# The v3 contract itself is covered in pds_spec.rb, for both spellings of the
# archive URL key. This spec covers what licenses contribute on top of it: the
# token scope, the `url` key its endpoints actually send, and its log wording.
RSpec.describe Gitlab::PackageMetadata::Connector::LicensesPds, feature_category: :software_composition_analysis do
  let(:base_uri) { 'https://pmdb-dist-svc.staging.runway.gitlab.net/v1/licenses' }
  let(:sync_config) do
    instance_double(::PackageMetadata::SyncConfiguration, base_uri: base_uri, purl_type: :npm)
  end

  let(:connector) { described_class.new(sync_config) }
  let(:checkpoint) { build(:pm_checkpoint, sequence: sequence) }
  let(:sequence) { 0 }

  let(:ijwt) { 'licenses-ijwt' }
  let(:cc_headers) { { 'x-gitlab-realm' => 'saas', 'x-gitlab-instance-id' => 'instance-uuid' } }
  let(:auth_headers) { cc_headers.merge('Authorization' => "Bearer #{ijwt}") }

  let(:reader) do
    instance_double(Gitlab::PackageMetadata::Connector::Archive::TarZstReader, each_entry: [entry])
  end

  let(:entry) do
    instance_double(Gitlab::PackageMetadata::Connector::Archive::TarZstReader::Entry,
      io: StringIO.new(%({"licenses":["MIT"]}\n)), chunk: 7)
  end

  before do
    allow(CloudConnector::Tokens).to receive(:get)
      .with(unit_primitive: :package_licenses, resource: :instance).and_return(ijwt)
    allow(CloudConnector).to receive(:headers).with(nil).and_return(cc_headers)
    allow(Gitlab::PackageMetadata::Connector::Archive::TarZstReader).to receive(:new).and_return(reader)
  end

  def http_response(code:, body: nil)
    instance_double(HTTParty::Response, code: code, success?: code.between?(200, 299), body: body)
  end

  describe '.unit_primitive' do
    it 'scopes the instance token to package licenses, not to another dataset' do
      expect(described_class.unit_primitive).to eq(:package_licenses)
    end

    # A token request for an unregistered primitive fails at runtime, not here,
    # so assert the name CloudConnector actually ships.
    it 'names a unit primitive CloudConnector knows about' do
      expect(::Gitlab::CloudConnector::DataModel::UnitPrimitive.find_by_name(described_class.unit_primitive))
        .to be_present
    end
  end

  describe '.archive_url_key' do
    it 'reads the archive URL from `url`, the name the licenses endpoints send' do
      expect(described_class.archive_url_key).to eq('url')
    end
  end

  describe '.instance_token' do
    it 'returns the package_licenses instance IJWT from CloudConnector' do
      expect(described_class.instance_token).to eq(ijwt)
    end
  end

  describe '#data_after' do
    context 'on first sync (GET /all)' do
      let(:all_response) do
        { 'until' => 1_700_000_000,
          'shards' => [
            { 'shard' => '00', 'url' => 'https://gcs/00.tar.zst' },
            { 'shard' => '0a', 'url' => 'https://gcs/0a.tar.zst' }
          ] }
      end

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/all", query: { purl_type: 'npm' }, headers: auth_headers)
          .and_return(http_response(code: 200, body: all_response.to_json))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/00.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 200, body: 'shard00'))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/0a.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 200, body: 'shard0a'))
      end

      it 'downloads each shard from its `url` with a licenses-scoped token', :aggregate_failures do
        files = connector.data_after(checkpoint).to_a

        expect(CloudConnector::Tokens).to have_received(:get)
          .with(unit_primitive: :package_licenses, resource: :instance)
        expect(files).to contain_exactly(
          an_object_having_attributes(sequence: 1_700_000_000, chunk: 0),
          an_object_having_attributes(sequence: 1_700_000_000, chunk: 10)
        )
        expect(files).to all(be_a(Gitlab::PackageMetadata::Connector::NdjsonDataFile))
      end

      it 'logs against the licenses dataset label' do
        allow(Gitlab::AppJsonLogger).to receive(:info)

        expect(Gitlab::AppJsonLogger).to receive(:info)
          .with(hash_including(message: 'Fetched package licenses from PDS',
            Labkit::Fields::CLASS_NAME => described_class.name))

        connector.data_after(checkpoint).to_a
      end
    end

    # The marker keeps first_sync? true, so /all is re-read and the shards already
    # ingested are skipped rather than downloaded again.
    context 'when resuming an interrupted first sync (GET /all)' do
      let(:sequence) { 1_700_000_000 }
      let(:checkpoint) do
        build(:pm_checkpoint, sequence: sequence, chunk: 0, full_sync_target_sequence: sequence)
      end

      let(:all_response) do
        { 'until' => 1_700_000_000,
          'shards' => [
            { 'shard' => '00', 'url' => 'https://gcs/00.tar.zst' },
            { 'shard' => '0a', 'url' => 'https://gcs/0a.tar.zst' }
          ] }
      end

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/all", query: { purl_type: 'npm' }, headers: auth_headers)
          .and_return(http_response(code: 200, body: all_response.to_json))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/0a.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 200, body: 'shard0a'))
      end

      it 'reads only the remaining shard from its `url`', :aggregate_failures do
        files = connector.data_after(checkpoint).to_a

        expect(files).to contain_exactly(an_object_having_attributes(sequence: 1_700_000_000, chunk: 10))
        expect(Gitlab::HTTP).not_to have_received(:get)
          .with('https://gcs/00.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
      end
    end

    # Licenses declare `url`, so an entry spelled the malware way is unusable
    # rather than something to fall back on.
    context 'when a shard entry carries `signed_url` instead of `url`' do
      let(:all_response) do
        { 'until' => 1_700_000_000,
          'shards' => [
            { 'shard' => '00', 'signed_url' => 'https://gcs/00.tar.zst' },
            { 'shard' => '01', 'url' => 'https://gcs/01.tar.zst' }
          ] }
      end

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/all", query: { purl_type: 'npm' }, headers: auth_headers)
          .and_return(http_response(code: 200, body: all_response.to_json))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/01.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 200, body: 'shard01'))
      end

      it 'skips it as malformed and still yields the well-formed shard', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:error)
          .with(hash_including(message: 'Skipping malformed PDS shard entry', shard: '00'))

        expect(connector.data_after(checkpoint).to_a.map(&:chunk)).to eq([1])
      end
    end

    # PDS keys by registry id, and eight of the configured purl types spell their
    # registry differently, so the translation has to happen on the way out.
    context 'when the registry id differs from the purl_type' do
      let(:sync_config) do
        instance_double(::PackageMetadata::SyncConfiguration, base_uri: base_uri, purl_type: :gem)
      end

      let(:all_response) do
        { 'until' => 1_700_000_000,
          'shards' => [{ 'shard' => '00', 'url' => 'https://gcs/00.tar.zst' }] }
      end

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/all", query: { purl_type: 'rubygem' }, headers: auth_headers)
          .and_return(http_response(code: 200, body: all_response.to_json))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/00.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 200, body: 'shard00'))
      end

      it 'requests /all with the registry id rather than the purl_type' do
        expect(connector.data_after(checkpoint).to_a).to contain_exactly(
          an_object_having_attributes(sequence: 1_700_000_000, chunk: 0)
        )
      end
    end

    context 'on incremental sync (GET /delta)' do
      let(:sequence) { 1_700_000_000 }
      let(:delta_response) do
        { 'purl_types' => { 'npm' => [{ 'delta' => '1700000600', 'url' => 'https://gcs/d.tar.zst' }] } }
      end

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/delta", query: { since: 'npm:1700000000' }, headers: auth_headers)
          .and_return(http_response(code: 200, body: delta_response.to_json))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/d.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 200, body: 'delta'))
      end

      it 'downloads the delta archive from its `url`' do
        expect(connector.data_after(checkpoint).to_a).to contain_exactly(
          an_object_having_attributes(sequence: 1_700_000_600, chunk: 7)
        )
      end
    end

    # Once every registry has been synced once, 204 is the routine answer.
    context 'when PDS has no new licenses for the registry (204)' do
      let(:sequence) { 1_700_000_000 }

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/delta", query: { since: 'npm:1700000000' }, headers: auth_headers)
          .and_return(http_response(code: 204))
      end

      it 'yields nothing and logs the no-op against the licenses dataset label', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:info)
          .with(hash_including(message: 'PDS reports no new package licenses', status: 204))

        expect(connector.data_after(checkpoint).to_a).to be_empty
      end
    end

    context 'when the archive download fails' do
      let(:all_response) do
        { 'until' => 1_700_000_000,
          'shards' => [{ 'shard' => '00', 'url' => 'https://gcs/00.tar.zst' }] }
      end

      before do
        allow(Gitlab::HTTP).to receive(:get)
          .with("#{base_uri}/all", query: { purl_type: 'npm' }, headers: auth_headers)
          .and_return(http_response(code: 200, body: all_response.to_json))
        allow(Gitlab::HTTP).to receive(:get)
          .with('https://gcs/00.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
          .and_return(http_response(code: 403))
      end

      it 'raises even though the manifest fetch succeeded', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:error).with(
          hash_including(message: 'Failed to download package licenses archive from signed URL', status: 403)
        )

        expect { connector.data_after(checkpoint).to_a }.to raise_error(described_class::ResponseError)
      end
    end

    # Six of the seventeen configured registry types are OS or distribution types
    # the licenses data does not cover, so this path is the norm for licenses
    # rather than an edge case.
    context 'when PDS does not serve licenses for the registry (400)' do
      before do
        allow(Gitlab::HTTP).to receive(:get)
          .and_return(http_response(code: 400, body: '{"error":"unknown purl_type: npm"}'))
      end

      it 'skips the registry rather than failing the run', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(
          hash_including(message: 'Skipping purl_type: PDS rejected the request', purl_type: :npm, status: 400)
        )

        expect(connector.data_after(checkpoint).to_a).to be_empty
      end
    end
  end

  describe '#delta_files_for' do
    let(:delta_response) do
      { 'purl_types' => {
        'npm' => [{ 'delta' => '1774625424', 'url' => 'https://gcs/npm-delta.tar.zst' }],
        'rubygem' => []
      } }
    end

    before do
      allow(Gitlab::HTTP).to receive(:get)
        .with("#{base_uri}/delta", hash_including(query: { since: ['npm:100', 'rubygem:200'] }, headers: auth_headers))
        .and_return(http_response(code: 200, body: delta_response.to_json))
      allow(Gitlab::HTTP).to receive(:get)
        .with('https://gcs/npm-delta.tar.zst', timeout: described_class::DOWNLOAD_TIMEOUT)
        .and_return(http_response(code: 200, body: 'npm-delta'))
    end

    it 'reads each bulk delta archive from its `url`, grouped by purl_type' do
      result = connector.delta_files_for({ 'npm' => 100, 'gem' => 200 })

      expect(result.transform_values { |files| files.to_a.map(&:sequence) })
        .to eq('npm' => [1_774_625_424], 'gem' => [])
    end
  end

  describe '#supported_registries' do
    it 'returns the registry ids PDS serves licenses for' do
      allow(Gitlab::HTTP).to receive(:get)
        .with("#{base_uri}/supported", headers: auth_headers)
        .and_return(http_response(code: 200, body: { registries: %w[npm rubygem pypi] }.to_json))

      expect(connector.supported_registries).to eq(%w[npm rubygem pypi])
    end
  end

  describe '#supported_registries caching', :use_clean_rails_memory_store_caching do
    # The cache key carries the unit primitive, so licenses and malware cannot
    # serve each other a cached registry list even on a shared endpoint.
    it 'does not share a cache entry with the malware dataset', :aggregate_failures do
      allow(CloudConnector::Tokens).to receive(:get)
        .with(unit_primitive: :malware_advisories, resource: :instance).and_return(ijwt)
      allow(Gitlab::HTTP).to receive(:get)
        .with("#{base_uri}/supported", headers: auth_headers)
        .and_return(http_response(code: 200, body: { registries: %w[npm] }.to_json),
          http_response(code: 200, body: { registries: %w[maven] }.to_json))

      expect(connector.supported_registries).to eq(%w[npm])
      expect(Gitlab::PackageMetadata::Connector::MalwarePds.new(sync_config).supported_registries).to eq(%w[maven])
    end
  end
end
