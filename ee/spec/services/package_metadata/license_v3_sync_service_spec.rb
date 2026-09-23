# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::LicenseV3SyncService, feature_category: :software_composition_analysis do
  describe '.data_type' do
    it 'names the licenses dataset' do
      expect(described_class.data_type).to eq('licenses')
    end

    it 'resolves to the licenses PDS connector' do
      expect(Gitlab::PackageMetadata::Connector::Pds.class_for(described_class.data_type))
        .to eq(Gitlab::PackageMetadata::Connector::LicensesPds)
    end
  end

  describe '.log_event' do
    it 'derives the log event from data_type' do
      expect(described_class.log_event).to eq('license_sync')
    end
  end

  describe '.dataset_label' do
    it 'derives the label from data_type' do
      expect(described_class.dataset_label).to eq('License')
    end
  end

  describe '.ingestion_service' do
    it 'ingests through the compressed package pipeline' do
      expect(described_class.ingestion_service)
        .to eq(PackageMetadata::Ingestion::CompressedPackage::IngestionService)
    end
  end

  describe '.fabricator_class' do
    it 'returns the data object fabricator' do
      expect(described_class.fabricator_class).to eq(PackageMetadata::DataObjectFabricator)
    end
  end

  describe '.offline_connector_class' do
    it 'reads the v3 vendor layout through the shared connector' do
      expect(described_class.offline_connector_class).to eq(Gitlab::PackageMetadata::Connector::OfflineV3)
    end
  end

  describe '.max_lease_length' do
    it 'matches the worker lease' do
      expect(described_class.max_lease_length).to eq(PackageMetadata::LicensesSyncWorker::LEASE_TIMEOUT)
    end
  end

  describe '.max_sync_duration' do
    it 'stays under the lease so the run stops before the lease expires' do
      expect(described_class.max_sync_duration).to be < described_class.max_lease_length
    end
  end

  describe '.ingest_slice_size' do
    it 'ingests in slices of 1000' do
      expect(described_class.ingest_slice_size).to eq(1_000)
    end
  end

  describe '.throttle_rate' do
    it 'pauses between slices' do
      expect(described_class.throttle_rate).to eq(0.25.seconds)
    end
  end

  describe '.execute' do
    let(:lease) { instance_double(Gitlab::ExclusiveLease) }

    before do
      allow(PackageMetadata::SyncConfiguration).to receive(:permitted_purl_types).and_return({ npm: 1 })
    end

    it 'loads checkpoints pinned to v3 for the PDS configuration' do
      expect(PackageMetadata::SyncConfiguration.license_configs.map(&:version_format).uniq).to eq(['v3'])

      # Stops the run right after the checkpoint load, before any PDS request.
      allow(Gitlab::PackageMetadata::Connector::LicensesPds).to receive(:instance_token).and_return('')
      expect(PackageMetadata::Checkpoint).to receive(:for_dataset).with('licenses', 'v3').and_call_original

      described_class.execute(lease: lease)
    end

    # The worker sends air-gapped installs to SyncService, so if one reached here the
    # v3-pinned checkpoint load would miss its rows. Stop before writing anything.
    it 'refuses to run the vendored v2 configuration' do
      allow(PackageMetadata::SyncConfiguration::Location).to receive(:for_licenses)
        .and_return([:offline, PackageMetadata::SyncConfiguration::Location::LICENSES_PATH])

      expect(PackageMetadata::Checkpoint).not_to receive(:for_dataset)
      expect { described_class.execute(lease: lease) }
        .to raise_error(ArgumentError, 'PackageMetadata::LicenseV3SyncService expects v3 sync configurations, got: v2')
    end
  end
end
