# frozen_string_literal: true

# The doubles and lets a v3 sync run needs. Everything is derived from
# described_class, so a subclass spec supplies nothing but the class itself --
# except the fabricator and ingestion service, which the host has to stub_const
# when those classes do not exist yet.
RSpec.shared_context 'with a v3 sync run' do
  # Only sequence, chunk and the snapshot flag matter here: the fabricator that reads
  # the io is stubbed, so StringIO suffices.
  def data_file(sequence, chunk, snapshot: false)
    Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(StringIO.new, sequence, chunk, snapshot: snapshot)
  end

  # A full-dataset shard: its own resume unit, keyed by chunk.
  def snapshot_file(sequence, chunk)
    data_file(sequence, chunk, snapshot: true)
  end

  # The fabricator's argument hash, so stubs and assertions name only the file.
  def ingest_args(file)
    { data_file: file, sync_config: sync_config }
  end

  let(:data_type) { described_class.data_type }
  let(:log_event) { described_class.log_event }
  let(:dataset_label) { described_class.dataset_label }
  let(:fabricator) { described_class.fabricator_class }
  let(:ingestion) { described_class.ingestion_service }
  let(:pds_connector_class) { Gitlab::PackageMetadata::Connector::Pds.class_for(data_type) }
  let(:pds_base_uri) { "https://pds.example/v1/#{data_type}" }
  let(:offline_base_uri) { "/vendor/package_metadata/#{data_type}" }

  let(:data_objects) { %i[object_a object_b] }
  let(:sync_config) do
    build(:pm_sync_config, data_type: data_type, storage_type: :pds,
      base_uri: pds_base_uri, version_format: 'v3', purl_type: 'npm')
  end

  let(:stop_signal) { instance_double(PackageMetadata::StopSignal, stop?: false) }
  let(:checkpoint) do
    instance_double(PackageMetadata::Checkpoint, first_sync?: false, sequence: 100, chunk: 0,
      full_sync_target_sequence: nil, update: true)
  end

  let(:files) { [] } # overridden per example; a default keeps the connector double buildable
  let(:connector) { instance_double(pds_connector_class, data_after: files) }

  before do
    allow(fabricator).to receive(:new).and_return(data_objects)
    allow(ingestion).to receive(:execute).and_return(true)
    allow(PackageMetadata::Checkpoint).to receive(:with_path_components).and_return(checkpoint)
    allow(pds_connector_class).to receive(:new).and_return(connector)
    allow(Gitlab::AppJsonLogger).to receive(:info)
    allow(Gitlab::AppJsonLogger).to receive(:debug)
    allow(Gitlab::AppJsonLogger).to receive(:error)
    stub_env('PM_SYNC_IN_DEV', 'true') # skip the inter-slice throttle sleep
  end
end

# The run shape every v3 dataset inherits from PackageMetadata::V3SyncService:
# per-archive ingestion and checkpointing, the /all snapshot bootstrap, stop-signal
# handling, /supported filtering, the bulk /delta path and the instance-token
# pre-flight. A new dataset gets all of it with `it_behaves_like 'a v3 sync service'`
# rather than copying its sibling's spec.
RSpec.shared_examples 'a v3 sync service' do
  include_context 'with a v3 sync run'

  describe '#execute' do
    subject(:execute) { described_class.new(sync_config, stop_signal).execute }

    context 'when ingestion is skipped' do
      let(:files) { [data_file(200, 0), data_file(300, 0), data_file(400, 0)] }

      before do
        allow(ingestion).to receive(:execute).and_return(false)
      end

      it 'validates every file without advancing the checkpoint', :aggregate_failures do
        execute

        expect(ingestion).to have_received(:execute).exactly(3).times
        expect(checkpoint).not_to have_received(:update)
      end
    end

    context 'when a file has mixed slice ingestion results' do
      let(:files) { [data_file(200, 0)] }
      let(:data_objects) { instance_double(Array) }

      before do
        allow(data_objects).to receive(:each_slice).and_yield([:slice_a]).and_yield([:slice_b])
        allow(ingestion).to receive(:execute).with([:slice_a]).and_return(false)
        allow(ingestion).to receive(:execute).with([:slice_b]).and_return(true)
      end

      it 'executes all slices and does not advance the checkpoint', :aggregate_failures do
        execute

        expect(ingestion).to have_received(:execute).with([:slice_a])
        expect(ingestion).to have_received(:execute).with([:slice_b])
        expect(checkpoint).not_to have_received(:update)
      end

      it 'tracks delta_not_persisted, so a registry that never advances is not reported as healthy' do
        expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_not_persisted")
          .with(additional_properties: { label: 'npm' })
      end
    end

    context 'with multiple files where an intermediate file is skipped' do
      let(:files) { [data_file(200, 0), data_file(300, 0), data_file(400, 0)] }

      before do
        allow(fabricator).to receive(:new)
          .with(**ingest_args(files[0])).and_return([:objects_200])
        allow(fabricator).to receive(:new)
          .with(**ingest_args(files[1])).and_return([:objects_300])
        allow(fabricator).to receive(:new)
          .with(**ingest_args(files[2])).and_return([:objects_400])

        allow(ingestion).to receive(:execute).with([:objects_200]).and_return(true)
        allow(ingestion).to receive(:execute).with([:objects_300]).and_return(false)
        allow(ingestion).to receive(:execute).with([:objects_400]).and_return(true)
      end

      it 'does not advance the checkpoint past the skipped file', :aggregate_failures do
        execute

        expect(checkpoint).to have_received(:update).with(sequence: 200, chunk: 0, full_sync_target_sequence: nil)
        expect(checkpoint).not_to have_received(:update).with(sequence: 300, chunk: 0, full_sync_target_sequence: nil)
        expect(checkpoint).not_to have_received(:update).with(sequence: 400, chunk: 0, full_sync_target_sequence: nil)
      end
    end

    context 'when an archive yields zero data slices' do
      let(:files) { [data_file(200, 0)] }
      let(:data_objects) { [] }

      it 'handles empty archives gracefully and advances the checkpoint' do
        execute

        expect(checkpoint).to have_received(:update).with(sequence: 200, chunk: 0, full_sync_target_sequence: nil)
      end
    end

    context 'with a multi-chunk archive followed by a second archive' do
      # Two chunks share sequence 200 (one archive); sequence 300 is a second archive.
      let(:files) { [data_file(200, 0), data_file(200, 1), data_file(300, 0)] }

      it 'ingests every file' do
        execute

        expect(ingestion).to have_received(:execute).exactly(3).times
      end

      it 'advances the checkpoint once per fully-ingested archive', :aggregate_failures do
        execute

        expect(checkpoint).to have_received(:update).with(sequence: 200, chunk: 1, full_sync_target_sequence: nil)
        expect(checkpoint).to have_received(:update).with(sequence: 300, chunk: 0, full_sync_target_sequence: nil)
      end
    end

    context 'when the checkpoint indicates a first sync (the /all snapshot)' do
      # A real checkpoint is used so full_sync_target_sequence reflects each update
      # (the marker rides along with every shard commit). sequence 0 => first_sync?.
      # Every shard shares one sequence (the snapshot `until`), differing by chunk;
      # here 1000 is the snapshot with shards 0, 1, 2.
      let(:checkpoint) do
        create(:pm_checkpoint, data_type: data_type, version_format: 'v3', purl_type: :npm,
          sequence: 0, chunk: 0, full_sync_target_sequence: nil)
      end

      let(:files) { [snapshot_file(1000, 0), snapshot_file(1000, 1), snapshot_file(1000, 2)] }

      it 'ingests every shard, advances per shard, and clears the marker on completion',
        :aggregate_failures do
        execute
        checkpoint.reload

        expect(checkpoint.sequence).to eq(1000)
        expect(checkpoint.chunk).to eq(2)
        expect(checkpoint.full_sync_target_sequence).to be_nil
        expect(checkpoint.first_sync?).to be(false)
      end

      context 'when a shard fails to persist mid-snapshot' do
        before do
          allow(fabricator).to receive(:new)
            .with(**ingest_args(files[0])).and_return([:shard_0])
          allow(fabricator).to receive(:new)
            .with(**ingest_args(files[1])).and_return([:shard_1])
          allow(fabricator).to receive(:new)
            .with(**ingest_args(files[2])).and_return([:shard_2])
          allow(ingestion).to receive(:execute).with([:shard_0]).and_return(true)
          allow(ingestion).to receive(:execute).with([:shard_1]).and_return(false)
          allow(ingestion).to receive(:execute).with([:shard_2]).and_return(true)
        end

        it 'stops at the last fully persisted shard and keeps the marker', :aggregate_failures do
          execute
          checkpoint.reload

          expect(checkpoint.sequence).to eq(1000)
          expect(checkpoint.chunk).to eq(0)
          expect(checkpoint.full_sync_target_sequence).to eq(1000)
        end

        it 'tracks full_not_persisted, the /all bootstrap counterpart of the delta case' do
          expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_full_not_persisted")
            .with(additional_properties: { label: 'npm' })
        end
      end

      context 'when the sync is interrupted mid-snapshot' do
        before do
          # One stop? call per file, before that file's ingest: #1 files[0] proceeds,
          # #2 files[1] stops. Shard 0 is ingested and committed, shard 1 never starts.
          allow(stop_signal).to receive(:stop?).and_return(false, true)
        end

        it 'keeps the last complete shard and the marker so the next run resumes /all',
          :aggregate_failures do
          execute
          checkpoint.reload

          expect(checkpoint.sequence).to eq(1000)
          expect(checkpoint.chunk).to eq(0)
          expect(checkpoint.full_sync_target_sequence).to eq(1000)
          expect(checkpoint.first_sync?).to be(true)
        end

        it 'ingests the committed shard and not the one it stops before', :aggregate_failures do
          # Ingesting shard 1 would be wasted work: the interrupt commits nothing, so the
          # next run re-reads it from the shard-0 checkpoint regardless.
          execute

          expect(fabricator).to have_received(:new).with(**ingest_args(files[0]))
          expect(fabricator).not_to have_received(:new).with(**ingest_args(files[1]))
        end

        it 'tracks the full_interrupted outcome' do
          expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_full_interrupted")
            .with(additional_properties: { label: 'npm' })
        end
      end

      context 'when the sync is interrupted before the first shard' do
        before do
          # Stop on the very first check, before anything is ingested.
          allow(stop_signal).to receive(:stop?).and_return(true)
        end

        it 'leaves the checkpoint untouched and ingests nothing', :aggregate_failures do
          execute
          checkpoint.reload

          expect(checkpoint.sequence).to eq(0)
          expect(checkpoint.chunk).to eq(0)
          expect(checkpoint.full_sync_target_sequence).to be_nil
          expect(fabricator).not_to have_received(:new)
        end

        it 'tracks the full_interrupted outcome even though nothing was ingested' do
          expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_full_interrupted")
            .with(additional_properties: { label: 'npm' })
        end
      end
    end

    context 'when a snapshot arrives after the first sync' do
      # Offline re-reads the vendor full_dataset whenever a newer one is copied in, so
      # a snapshot reaches a registry long past its first sync, and its shards still
      # have to resume one at a time.
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/628423
      let(:checkpoint) do
        create(:pm_checkpoint, data_type: data_type, version_format: 'v3', purl_type: :npm,
          sequence: 500, chunk: 0, full_sync_target_sequence: nil)
      end

      let(:files) { [snapshot_file(1000, 0), snapshot_file(1000, 1), snapshot_file(1000, 2)] }

      before do
        # #1 = shard 0 (proceeds), #2 = shard 1 (stops), so only shard 0 commits.
        allow(stop_signal).to receive(:stop?).and_return(false, true)
      end

      it 'commits the finished shard and marks the snapshot for resume', :aggregate_failures do
        execute
        checkpoint.reload

        expect(checkpoint.sequence).to eq(1000)
        expect(checkpoint.chunk).to eq(0)
        expect(checkpoint.full_sync_target_sequence).to eq(1000)
        expect(checkpoint.first_sync?).to be(true)
      end

      it 'reports the mode it read, not the delta the checkpoint implied' do
        execute

        expect(Gitlab::AppJsonLogger).to have_received(:info)
          .with(hash_including(phase: 'interrupted', sync_mode: 'full'))
      end
    end

    context 'with a snapshot and a delta in one stream' do
      # One offline run can read both: the snapshot by shard, the delta as a whole.
      let(:checkpoint) do
        create(:pm_checkpoint, data_type: data_type, version_format: 'v3', purl_type: :npm,
          sequence: 500, chunk: 0, full_sync_target_sequence: nil)
      end

      let(:files) { [snapshot_file(1000, 0), snapshot_file(1000, 1), data_file(1200, 0), data_file(1200, 1)] }

      it 'ends on the delta with the snapshot marker cleared', :aggregate_failures do
        execute
        checkpoint.reload

        expect(checkpoint.sequence).to eq(1200)
        expect(checkpoint.chunk).to eq(1)
        expect(checkpoint.full_sync_target_sequence).to be_nil
      end

      context 'when the delta is interrupted after the snapshot finished' do
        before do
          # #1, #2 = the two shards (proceed), #3 = the delta's first file (stops).
          allow(stop_signal).to receive(:stop?).and_return(false, false, true)
        end

        it 'keeps the whole snapshot and leaves the delta for the next run', :aggregate_failures do
          execute
          checkpoint.reload

          expect(checkpoint.sequence).to eq(1000)
          expect(checkpoint.chunk).to eq(1)
          expect(checkpoint.full_sync_target_sequence).to eq(1000)
        end
      end
    end

    context 'when a full-sync shard tar holds multiple entries' do
      # Entries of one shard share a chunk, so the shard must be checkpointed only
      # after all its entries land -- otherwise a resume would skip the rest of the
      # shard (chunk <= checkpoint.chunk). Shard 0 here has two entries (chunk 0).
      let(:checkpoint) do
        create(:pm_checkpoint, data_type: data_type, version_format: 'v3', purl_type: :npm,
          sequence: 0, chunk: 0, full_sync_target_sequence: nil)
      end

      let(:files) { [snapshot_file(1000, 0), snapshot_file(1000, 0), snapshot_file(1000, 1)] }

      before do
        # #1 = entry 0 of shard 0 (proceeds), #2 = entry 1 of the same shard (stops),
        # so shard 0 is only half ingested and must not be checkpointed.
        allow(stop_signal).to receive(:stop?).and_return(false, true)
      end

      it 'does not checkpoint the shard after only its first entry', :aggregate_failures do
        execute
        checkpoint.reload

        expect(ingestion).to have_received(:execute).once
        expect(checkpoint.sequence).to eq(0)
        expect(checkpoint.chunk).to eq(0)
        expect(checkpoint.full_sync_target_sequence).to be_nil
      end
    end

    context 'when the snapshot is already fully ingested but the marker is still set' do
      # A prior run interrupted right as the last shard finished would leave
      # full_sync_target_sequence set; data_after now yields nothing.
      let(:checkpoint) do
        create(:pm_checkpoint, data_type: data_type, version_format: 'v3', purl_type: :npm,
          sequence: 1000, chunk: 63, full_sync_target_sequence: 1000)
      end

      let(:files) { [] }

      it 'clears the marker so the next run switches to /delta', :aggregate_failures do
        execute
        checkpoint.reload

        expect(checkpoint.full_sync_target_sequence).to be_nil
        expect(checkpoint.first_sync?).to be(false)
      end
    end

    context 'when the stop signal fires mid-archive' do
      let(:files) { [data_file(200, 0), data_file(200, 1)] }

      before do
        # #1 = files[0] (proceeds), #2 = files[1] (stops), leaving archive 200 incomplete.
        allow(stop_signal).to receive(:stop?).and_return(false, true)
      end

      it 'leaves the incomplete archive uncommitted so the next run re-fetches it', :aggregate_failures do
        execute

        expect(ingestion).to have_received(:execute).once
        expect(checkpoint).not_to have_received(:update)
      end

      it 'logs the interruption with the shard and sequence it stopped at' do
        execute

        expect(Gitlab::AppJsonLogger).to have_received(:info)
          .with(hash_including(phase: 'interrupted', to_sequence: 100, to_chunk: 0))
      end

      it 'tracks the delta_interrupted outcome' do
        expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_interrupted")
          .with(additional_properties: { label: 'npm' })
      end
    end

    # The stop check runs before the ingest, so this run ends with
    # files_ingested == 0 -- the same count as a registry that had nothing to
    # read. Only the interrupt separates the two.
    context 'when the stop signal fires before the first archive' do
      let(:files) { [data_file(200, 0)] }

      before do
        allow(stop_signal).to receive(:stop?).and_return(true)
      end

      it 'tracks delta_interrupted rather than delta_up_to_date' do
        expect { execute }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_interrupted")
            .with(additional_properties: { label: 'npm' })
          .and not_trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_up_to_date")
      end
    end

    context 'when logging the sync lifecycle' do
      let(:files) { [data_file(300, 0)] }

      it 'logs started then completed with correlation ids', :aggregate_failures do
        execute

        expect(Gitlab::AppJsonLogger).to have_received(:info)
          .with(hash_including(phase: 'started', event: log_event,
            purl_type: 'npm', data_type: data_type, resuming: false))
        expect(Gitlab::AppJsonLogger).to have_received(:info)
          .with(hash_including(phase: 'completed', files_ingested: 1, sync_mode: 'delta'))
      end

      it 'leaves the mode off the started line, where it would only be a guess' do
        execute

        expect(Gitlab::AppJsonLogger).not_to have_received(:info)
          .with(hash_including(phase: 'started', sync_mode: anything))
      end

      it 'tracks the delta_completed outcome with purl_type as the label' do
        expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_completed")
          .with(additional_properties: { label: 'npm' })
      end

      context 'when the checkpoint indicates a first sync' do
        before do
          allow(checkpoint).to receive(:first_sync?).and_return(true)
        end

        it 'tracks the full_completed outcome so full and delta runs stay separable' do
          expect { execute }.to trigger_internal_events("sync_pmdb_v3_#{data_type}_full_completed")
            .with(additional_properties: { label: 'npm' })
        end
      end

      context 'when resuming an interrupted first sync' do
        before do
          allow(checkpoint).to receive_messages(first_sync?: true, full_sync_target_sequence: 500,
            sequence: 500, chunk: 2)
        end

        it 'logs the resume with the shard and sequence it continues from' do
          execute

          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(phase: 'started', resuming: true,
              from_sequence: 500, from_chunk: 2))
        end
      end

      context 'when a snapshot arrives on a run the checkpoint called a delta' do
        let(:files) { [snapshot_file(1000, 0), snapshot_file(1000, 1)] }

        it 'reports full, not the delta the checkpoint implied' do
          execute

          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(phase: 'completed', sync_mode: 'full'))
        end
      end

      context 'when one run reads a snapshot and a delta' do
        let(:files) { [snapshot_file(1000, 0), data_file(1200, 0)] }

        it 'reports the run as mixed' do
          execute

          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(phase: 'completed', sync_mode: 'mixed'))
        end
      end

      context 'when the stream is empty' do
        let(:files) { [] }

        it 'omits the mode, since the run read nothing to judge it by', :aggregate_failures do
          execute

          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(hash_including(phase: 'completed', files_ingested: 0))
          expect(Gitlab::AppJsonLogger).not_to have_received(:info)
            .with(hash_including(sync_mode: anything))
        end
      end
    end

    context 'when a delta run finds no new archives' do
      let(:files) { [] }

      it 'tracks delta_up_to_date rather than delta_completed' do
        expect { execute }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_up_to_date")
            .with(additional_properties: { label: 'npm' })
          .and not_trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_completed")
      end
    end

    # A rejected request yields nil, not an empty stream: reporting it as empty
    # would read as a current registry on a delta, and as a finished snapshot on
    # a full run.
    context 'when PDS rejects this registry\'s request' do
      let(:files) { nil }

      it 'tracks delta_failed and ingests nothing', :aggregate_failures do
        expect { execute }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_failed")
            .with(additional_properties: { label: 'npm' })
          .and not_trigger_internal_events(
            "sync_pmdb_v3_#{data_type}_delta_up_to_date",
            "sync_pmdb_v3_#{data_type}_delta_completed")

        expect(ingestion).not_to have_received(:execute)
      end

      it 'logs the rejection with the mode the run would have taken' do
        execute

        expect(Gitlab::AppJsonLogger).to have_received(:error).with(
          hash_including(message: a_string_matching(/sync stopped: PDS rejected the request/),
            event: log_event, phase: 'fetch_rejected', sync_mode: 'delta', purl_type: 'npm'))
      end

      context 'on a first sync' do
        before do
          allow(checkpoint).to receive_messages(first_sync?: true, full_sync_target_sequence: nil)
        end

        it 'tracks full_failed rather than full_completed' do
          expect { execute }
            .to trigger_internal_events("sync_pmdb_v3_#{data_type}_full_failed")
              .with(additional_properties: { label: 'npm' })
            .and not_trigger_internal_events("sync_pmdb_v3_#{data_type}_full_completed")
        end
      end
    end

    context 'when ingestion raises mid-run' do
      let(:files) { [data_file(300, 0)] }

      before do
        allow(ingestion).to receive(:execute).and_raise(StandardError.new('boom'))
      end

      it 'tracks delta_failed and re-raises', :aggregate_failures do
        expect { execute }
          .to raise_error(StandardError, 'boom')
          .and trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_failed")
            .with(additional_properties: { label: 'npm' })
      end

      context 'when the checkpoint indicates a first sync' do
        before do
          allow(checkpoint).to receive(:first_sync?).and_return(true)
        end

        it 'tracks full_failed so a failed bootstrap is separable from a failed delta' do
          expect { execute }
            .to raise_error(StandardError, 'boom')
            .and trigger_internal_events("sync_pmdb_v3_#{data_type}_full_failed")
              .with(additional_properties: { label: 'npm' })
        end
      end
    end

    context 'when the storage type has no connector' do
      let(:sync_config) do
        build(:pm_sync_config, data_type: data_type, storage_type: :unknown,
          base_uri: 'x', version_format: 'v3', purl_type: 'npm')
      end

      it 'raises UnknownAdapterError' do
        expect { execute }.to raise_error(described_class::UnknownAdapterError)
      end
    end

    context 'with files supplied by the caller (the bulk /delta path)' do
      subject(:execute) { described_class.new(sync_config, stop_signal).ingest_prefetched(files) }

      let(:files) { [data_file(300, 0)] }

      it 'ingests the supplied files and does not ask the connector to fetch', :aggregate_failures do
        execute

        expect(ingestion).to have_received(:execute)
        expect(connector).not_to have_received(:data_after)
      end
    end

    context 'with a multi-archive bulk stream interrupted mid-registry' do
      subject(:execute) { described_class.new(sync_config, stop_signal).ingest_prefetched(files) }

      let(:files) { [data_file(300, 0), data_file(400, 0)] }

      before do
        allow(stop_signal).to receive(:stop?).and_return(false, true)
      end

      it 'commits the completed archive and leaves the interrupted one for the next run', :aggregate_failures do
        execute

        expect(checkpoint).to have_received(:update).with(sequence: 300, chunk: 0, full_sync_target_sequence: nil)
        expect(checkpoint).not_to have_received(:update).with(sequence: 400, chunk: 0, full_sync_target_sequence: nil)
        expect(fabricator).not_to have_received(:new).with(**ingest_args(files[1]))
      end
    end
  end

  describe '.execute' do
    let(:lease) { instance_double(Gitlab::ExclusiveLease, ttl: 1000) }
    let(:files) { [data_file(300, 0)] }

    let(:npm_config) { sync_config }
    let(:gem_config) do
      build(:pm_sync_config, data_type: data_type, storage_type: :pds,
        base_uri: pds_base_uri, version_format: 'v3', purl_type: 'gem')
    end

    let(:npm_checkpoint) do
      instance_double(PackageMetadata::Checkpoint,
        purl_type: 'npm', first_sync?: false, sequence: 100, chunk: 0,
        full_sync_target_sequence: nil, update: true)
    end

    let(:gem_checkpoint) do
      instance_double(PackageMetadata::Checkpoint,
        purl_type: 'gem', first_sync?: false, sequence: 200, chunk: 0,
        full_sync_target_sequence: nil, update: true)
    end

    before do
      allow(PackageMetadata::SyncConfiguration).to receive(:configs_for)
        .with(data_type).and_return([npm_config, gem_config])
      allow(PackageMetadata::Checkpoint).to receive(:for_dataset).with(data_type, 'v3')
        .and_return([npm_checkpoint, gem_checkpoint])
      allow(connector).to receive_messages(
        delta_files_for: { 'npm' => files, 'gem' => [] }, supported_registries: %w[npm rubygem],
        delta_entry_counts: { 'npm' => 1, 'gem' => 0 })
      allow(pds_connector_class).to receive(:instance_token).and_return('test-ijwt')
    end

    context 'when the instance token (IJWT) is unavailable' do
      it 'stops the run without any PDS call and logs when the token is empty', :aggregate_failures do
        allow(pds_connector_class).to receive(:instance_token).and_return('')

        described_class.execute(lease: lease)

        expect(connector).not_to have_received(:supported_registries)
        expect(connector).not_to have_received(:delta_files_for)
        expect(Gitlab::AppJsonLogger).to have_received(:error).with(
          hash_including(message: a_string_matching(/instance token \(IJWT\) is empty/),
            event: log_event, phase: 'aborted_no_token'))
      end

      it 'tracks the label-less aborted_no_token event, the run ending before any registry' do
        allow(pds_connector_class).to receive(:instance_token).and_return('')

        expect { described_class.execute(lease: lease) }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_aborted_no_token")
          .with(category: described_class.name)
      end

      it 'stops the run and logs when acquiring the token raises', :aggregate_failures do
        allow(pds_connector_class).to receive(:instance_token).and_raise(StandardError.new('boom'))

        described_class.execute(lease: lease)

        expect(connector).not_to have_received(:delta_files_for)
        expect(Gitlab::AppJsonLogger).to have_received(:error).with(
          hash_including(message: a_string_matching(/could not obtain the instance token/),
            phase: 'aborted_no_token'))
      end

      it 'tracks aborted_no_token on the raising branch too' do
        allow(pds_connector_class).to receive(:instance_token).and_raise(StandardError.new('boom'))

        expect { described_class.execute(lease: lease) }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_aborted_no_token")
          .with(category: described_class.name)
      end
    end

    # .execute builds its own StopSignal from the lease, so the shared double has
    # to be substituted in to exercise a run whose budget is already spent.
    context 'when the stop signal is already set before any registry runs' do
      before do
        allow(PackageMetadata::StopSignal).to receive(:new).and_return(stop_signal)
        allow(stop_signal).to receive(:stop?).and_return(true)
      end

      it 'tracks a skip for every registry it never started and ingests nothing', :aggregate_failures do
        expect { described_class.execute(lease: lease) }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_skipped_stop_signal")
            .with(additional_properties: { label: 'npm' })
          .and trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_skipped_stop_signal")
            .with(additional_properties: { label: 'gem' })

        expect(ingestion).not_to have_received(:execute)
      end

      # A registry with no checkpoint yet routes to the individual path instead of
      # the bulk /delta, and skips through stop_before_sync?.
      context 'with a registry that has never synced' do
        before do
          allow(npm_checkpoint).to receive(:first_sync?).and_return(true)
        end

        it 'tracks skipped_stop_signal for the individually-synced registry' do
          expect { described_class.execute(lease: lease) }
            .to trigger_internal_events("sync_pmdb_v3_#{data_type}_skipped_stop_signal")
              .with(additional_properties: { label: 'npm' })
            .and trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_skipped_stop_signal")
              .with(additional_properties: { label: 'gem' })
        end
      end
    end

    context 'when the bulk /delta fetch raises' do
      before do
        allow(connector).to receive(:delta_files_for).and_raise(StandardError.new('boom'))
      end

      it 'tracks bulk_delta_failed for every queued registry and re-raises', :aggregate_failures do
        expect { described_class.execute(lease: lease) }
          .to raise_error(StandardError, 'boom')
          .and trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_failed")
            .with(additional_properties: { label: 'npm' })
          .and trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_failed")
            .with(additional_properties: { label: 'gem' })
      end
    end

    # PDS answers the bulk request for nobody when it rejects it, so the run has
    # to stop before the per-registry loop: ingesting an empty stream for each
    # would report the cycle as delta_up_to_date across the board.
    context 'when PDS rejects the bulk /delta request' do
      before do
        allow(connector).to receive(:delta_files_for).and_return(nil)
      end

      it 'tracks bulk_delta_failed for every queued registry', :aggregate_failures do
        expect { described_class.execute(lease: lease) }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_failed")
            .with(additional_properties: { label: 'npm' })
          .and trigger_internal_events("sync_pmdb_v3_#{data_type}_bulk_delta_failed")
            .with(additional_properties: { label: 'gem' })
      end

      it 'does not report any registry as up to date, or ingest anything', :aggregate_failures do
        expect { described_class.execute(lease: lease) }
          .to not_trigger_internal_events(
            "sync_pmdb_v3_#{data_type}_delta_up_to_date",
            "sync_pmdb_v3_#{data_type}_delta_backlog")

        expect(ingestion).not_to have_received(:execute)
      end

      it 'logs the failure without an error type, no exception having been raised' do
        described_class.execute(lease: lease)

        expect(Gitlab::AppJsonLogger).to have_received(:error).with(
          hash_including(message: a_string_matching(/bulk delta failed/),
            event: log_event, phase: 'bulk_delta_failed', purl_types: %w[npm gem]))
      end
    end

    it 'tracks how far behind each registry was, so a caught-up instance is distinguishable',
      :aggregate_failures do
      expect { described_class.execute(lease: lease) }
        .to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_backlog")
          .with(additional_properties: { label: 'npm', value: 1 })
        .and trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_backlog")
          .with(additional_properties: { label: 'gem', value: 0 })
    end

    it 'tracks delta_up_to_date for a registry PDS had no new archives for' do
      expect { described_class.execute(lease: lease) }
        .to trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_up_to_date")
          .with(additional_properties: { label: 'gem' })
    end

    it 'loads every registry checkpoint in a single query' do
      described_class.execute(lease: lease)

      expect(PackageMetadata::Checkpoint).to have_received(:for_dataset).once
    end

    it 'issues a single bulk /delta call covering every already-synced registry', :aggregate_failures do
      described_class.execute(lease: lease)

      expect(connector).to have_received(:delta_files_for)
        .with({ 'npm' => 100, 'gem' => 200 }).once
      expect(connector).not_to have_received(:data_after)
    end

    it 'ingests the bulk-delta archives and advances each registry checkpoint independently',
      :aggregate_failures do
      described_class.execute(lease: lease)

      expect(ingestion).to have_received(:execute).at_least(:once)
      expect(npm_checkpoint).to have_received(:update).with(sequence: 300, chunk: 0, full_sync_target_sequence: nil)
    end

    context 'when PDS does not serve a configured registry' do
      before do
        allow(connector).to receive(:supported_registries).and_return(['npm'])
      end

      it 'skips the unsupported registry and logs the drop', :aggregate_failures do
        described_class.execute(lease: lease)

        expect(connector).to have_received(:delta_files_for).with({ 'npm' => 100 }).once
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          hash_including(
            message: "#{dataset_label} sync: registries not served by PDS, skipped",
            phase: 'unsupported_skipped', purl_types: ['gem'], registries: ['rubygem']))
      end

      # The kept registry emits its own outcome in the same run, so both are asserted.
      it 'tracks skipped_unsupported for the dropped registry' do
        expect { described_class.execute(lease: lease) }
          .to trigger_internal_events("sync_pmdb_v3_#{data_type}_skipped_unsupported")
            .with(additional_properties: { label: 'gem' })
          .and trigger_internal_events("sync_pmdb_v3_#{data_type}_delta_completed")
            .with(additional_properties: { label: 'npm' })
      end
    end

    context 'when the /supported endpoint is unavailable' do
      before do
        allow(connector).to receive(:supported_registries).and_return(nil)
      end

      it 'falls back to syncing every configured registry' do
        described_class.execute(lease: lease)

        expect(connector).to have_received(:delta_files_for).with({ 'npm' => 100, 'gem' => 200 }).once
      end
    end

    context 'when PDS configs span more than one endpoint' do
      let(:gem_config) do
        build(:pm_sync_config, data_type: data_type, storage_type: :pds,
          base_uri: "https://other.example/v1/#{data_type}", version_format: 'v3', purl_type: 'gem')
      end

      it 'raises rather than filtering registries against one endpoint' do
        expect { described_class.execute(lease: lease) }.to raise_error(ArgumentError, /one PDS endpoint/)
      end
    end

    context 'when no registry is PDS-backed (offline only)' do
      let(:offline_config) do
        build(:pm_sync_config, data_type: data_type, storage_type: :offline,
          base_uri: offline_base_uri, version_format: 'v3', purl_type: 'npm')
      end

      it 'returns the syncs unchanged without querying /supported', :aggregate_failures do
        syncs = [{ config: offline_config, checkpoint: npm_checkpoint }]

        expect(pds_connector_class).not_to receive(:new)
        expect(described_class.send(:filter_to_supported, syncs, 'batch-id')).to eq(syncs)
      end

      it 'is not PDS-backed, so the run skips the IJWT check entirely' do
        syncs = [{ config: offline_config, checkpoint: npm_checkpoint }]

        expect(described_class.send(:pds_backed?, syncs)).to be(false)
      end
    end

    context 'when a registry has no persisted checkpoint yet (first sync)' do
      before do
        allow(PackageMetadata::Checkpoint).to receive(:for_dataset).and_return([])
      end

      it 'bootstraps it with individual /all fetches, not the bulk /delta call', :aggregate_failures do
        described_class.execute(lease: lease)

        expect(connector).to have_received(:data_after).at_least(:once)
        expect(connector).not_to have_received(:delta_files_for)
      end
    end

    context 'when the run is interrupted between registries (deploy / job timeout)' do
      let(:interrupt_signal) { instance_double(PackageMetadata::StopSignal) }

      before do
        allow(connector).to receive(:delta_files_for)
          .and_return('npm' => [data_file(300, 0)], 'gem' => [data_file(400, 0)])

        allow(PackageMetadata::StopSignal).to receive(:new).and_return(interrupt_signal)
        # Four stop? checks in order: (1) the group pre-fetch guard, (2) npm's
        # between-registry guard, (3) npm's mid-archive check, (4) gem's
        # between-registry guard. Only the last is true, so npm runs to completion
        # and gem is skipped before it starts.
        allow(interrupt_signal).to receive(:stop?).and_return(false, false, false, true)
      end

      it 'commits the finished registry and leaves the untouched ones for the next run', :aggregate_failures do
        described_class.execute(lease: lease)

        expect(npm_checkpoint).to have_received(:update).with(sequence: 300, chunk: 0, full_sync_target_sequence: nil)
        expect(gem_checkpoint).not_to have_received(:update)
      end
    end

    context 'when the stop signal is already tripped before the bulk fetch' do
      let(:tripped_signal) { instance_double(PackageMetadata::StopSignal, stop?: true) }

      before do
        allow(PackageMetadata::StopSignal).to receive(:new).and_return(tripped_signal)
      end

      it 'logs one bulk-skip event and does not fetch or ingest', :aggregate_failures do
        described_class.execute(lease: lease)

        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          hash_including(
            message: "#{dataset_label} bulk delta skipped: stop signal before bulk fetch",
            phase: 'bulk_delta_skipped'
          )
        )
        expect(connector).not_to have_received(:delta_files_for)
        expect(ingestion).not_to have_received(:execute)
      end
    end
  end
end
