# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::V3SyncService, feature_category: :software_composition_analysis do
  # The run itself is covered through the subclass specs. What is asserted here is
  # the contract a new dataset has to satisfy, so a half-configured subclass fails
  # loudly instead of syncing the wrong dataset.
  describe 'the dataset contract' do
    let(:required_hooks) do
      %i[data_type fabricator_class ingestion_service
        max_lease_length max_sync_duration ingest_slice_size throttle_rate log_event]
    end

    it 'raises for every hook a subclass must supply', :aggregate_failures do
      required_hooks.each do |hook|
        expect { described_class.public_send(hook) }
          .to raise_error(Gitlab::AbstractMethodError), "expected .#{hook} to be abstract"
      end
    end

    it 'is satisfied by MalwareAdvisorySyncService, so no abstract hook survives a real run',
      :aggregate_failures do
      required_hooks.each do |hook|
        expect { PackageMetadata::MalwareAdvisorySyncService.public_send(hook) }
          .not_to raise_error, "expected .#{hook} to be supplied"
      end
    end

    it 'is satisfied by LicenseV3SyncService', :aggregate_failures do
      required_hooks.each do |hook|
        expect { PackageMetadata::LicenseV3SyncService.public_send(hook) }
          .not_to raise_error, "expected .#{hook} to be supplied"
      end
    end

    it 'supplies the shared offline connector, which every v3 dataset reads the same way', :aggregate_failures do
      expect(described_class.offline_connector_class)
        .to eq(Gitlab::PackageMetadata::Connector::OfflineV3)
      expect(PackageMetadata::MalwareAdvisorySyncService.offline_connector_class)
        .to eq(Gitlab::PackageMetadata::Connector::OfflineV3)
      expect(PackageMetadata::LicenseV3SyncService.offline_connector_class)
        .to eq(Gitlab::PackageMetadata::Connector::OfflineV3)
    end

    it 'derives dataset_label from data_type so a subclass need not restate it' do
      subclass = Class.new(described_class) do
        def self.data_type
          'malware_advisories'
        end
      end

      expect(subclass.dataset_label).to eq('Malware advisory')
    end
  end

  # The allowlist is what stops a new dataset from emitting an event that has no
  # definition file in ee/config/events, which would fail internal events
  # validation in production rather than at review time.
  describe '.track_sync_outcome' do
    let(:tracked_events) do
      described_class::TRACKED_DATA_TYPES.product(described_class::SYNC_OUTCOMES)
        .map { |data_type, outcome| "sync_pmdb_v3_#{data_type}_#{outcome}" }
    end

    # category is the dataset subclass, not this base class, so it is stated
    # explicitly rather than inferred from described_class.
    it 'emits for a data type that has a definition file' do
      expect { PackageMetadata::MalwareAdvisorySyncService.track_sync_outcome(nil, 'aborted_no_token') }
        .to trigger_internal_events('sync_pmdb_v3_malware_advisories_aborted_no_token')
        .with(category: 'PackageMetadata::MalwareAdvisorySyncService')
    end

    it 'increments the count metric for an outcome' do
      expect { PackageMetadata::MalwareAdvisorySyncService.track_sync_outcome(nil, 'aborted_no_token') }
        .to increment_usage_metrics('counts.count_total_sync_pmdb_v3_malware_advisories_aborted_no_token')
    end

    it 'adds the backlog value to the sum metric and counts the observation' do
      config = build(:pm_sync_config, data_type: 'malware_advisories', purl_type: 'npm',
        version_format: PackageMetadata::SyncConfiguration::VERSION_FORMAT_V3)

      expect { PackageMetadata::MalwareAdvisorySyncService.track_sync_outcome(config, 'delta_backlog', value: 3) }
        .to trigger_internal_events('sync_pmdb_v3_malware_advisories_delta_backlog')
        .with(category: 'PackageMetadata::MalwareAdvisorySyncService',
          additional_properties: { label: 'npm', value: 3 })
        .and increment_usage_metrics('sums.sum_total_sync_pmdb_v3_malware_advisories_delta_backlog_weekly').by(3)
        .and increment_usage_metrics('counts.count_total_sync_pmdb_v3_malware_advisories_delta_backlog_weekly')
    end

    it 'stays silent for a data type outside the allowlist' do
      subclass = Class.new(described_class) do
        def self.data_type
          'cve_enrichment'
        end
      end

      expect { subclass.track_sync_outcome(nil, 'aborted_no_token') }.not_to trigger_internal_events
    end

    it 'raises in development for an outcome with no definition file' do
      expect { PackageMetadata::MalwareAdvisorySyncService.track_sync_outcome(nil, 'bogus_outcome') }
        .to raise_error(ArgumentError, /unknown v3 sync outcome: bogus_outcome/)
    end

    it 'stays silent in production for an outcome with no definition file' do
      expect(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception).with(instance_of(ArgumentError))

      expect { PackageMetadata::MalwareAdvisorySyncService.track_sync_outcome(nil, 'bogus_outcome') }
        .not_to trigger_internal_events
    end

    it 'has a definition file for every outcome it accepts', :aggregate_failures do
      tracked_events.each do |event|
        path = Rails.root.join('ee/config/events', "#{event}.yml")

        expect(path).to exist, "expected a definition file at #{path}"
      end
    end

    # Events alone only reach Snowplow; Service Ping reports metrics, so an
    # outcome without one is invisible on instances that send nothing else.
    #
    # delta_backlog is a measurement rather than an outcome, so it carries both a
    # sum and a count: the sum alone reads zero whether PDS reported no backlog or
    # no bulk run happened, and only the count tells those apart. Both are asserted,
    # in both time frames, since a metric dropping one still reports under the other.
    it 'has a Service Ping metric for every outcome it accepts', :aggregate_failures do
      definitions = Gitlab::Usage::MetricDefinition.not_removed
      backlog_suffixes = %w[_weekly _monthly]

      tracked_events.each do |event|
        expected = if event.end_with?('_delta_backlog')
                     backlog_suffixes.flat_map do |suffix|
                       [["sums.sum_total_#{event}#{suffix}", true], ["counts.count_total_#{event}#{suffix}", false]]
                     end
                   else
                     [["counts.count_total_#{event}", false]]
                   end

        expected.each do |key_path, summed|
          definition = definitions[key_path]

          expect(definition).to be_present, "expected a metric #{key_path} in ee/config/metrics"
          next unless definition

          expect(definition.events).to have_key(event)
          expect(definition.event_selection_rules.first.sum?).to eq(summed),
            "expected #{key_path} to #{summed ? 'sum(value)' : 'count events'}"
        end
      end
    end
  end

  describe '.execute' do
    let(:lease) { instance_double(Gitlab::ExclusiveLease) }
    let(:subclass) do
      Class.new(PackageMetadata::MalwareAdvisorySyncService) do
        def self.name
          'PackageMetadata::TestSyncService'
        end
      end
    end

    # A v2 config would miss the v3-pinned checkpoint load and then advance a v2
    # row instead, so the run has to stop before it writes anything.
    it 'refuses to run a dataset whose configs are not v3' do
      v2_config = PackageMetadata::SyncConfiguration.new(
        'malware_advisories', :offline, 'path', PackageMetadata::SyncConfiguration::VERSION_FORMAT_V2, 'npm')
      allow(PackageMetadata::SyncConfiguration).to receive(:configs_for).and_return([v2_config])

      expect(PackageMetadata::Checkpoint).not_to receive(:for_dataset)
      expect { subclass.execute(lease: lease) }
        .to raise_error(ArgumentError, 'PackageMetadata::TestSyncService expects v3 sync configurations, got: v2')
    end
  end
end
