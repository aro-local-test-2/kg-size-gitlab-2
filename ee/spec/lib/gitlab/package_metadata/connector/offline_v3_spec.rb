# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::PackageMetadata::Connector::OfflineV3, feature_category: :software_composition_analysis do
  let(:base_uri) { '/vendor/malware_advisories' }
  let(:sync_config) do
    PackageMetadata::SyncConfiguration.new('malware_advisories', :offline, base_uri, 'v3', :npm)
  end

  let(:connector) { described_class.new(sync_config) }
  let(:full_dataset_dir) { File.join(base_uri, 'v3', 'npm', 'full_dataset') }
  let(:deltas_dir) { File.join(base_uri, 'v3', 'npm', 'deltas') }
  let(:checkpoint_path) { File.join(full_dataset_dir, 'checkpoint.json') }
  let(:shards) { ['00.tar.zst', '0a.tar.zst'] }
  # No deltas on disk unless a context says otherwise, so the snapshot contexts
  # below describe an instance that has only ever been given full datasets.
  let(:deltas) { [] }

  # A first-sync checkpoint (sequence 0) so the snapshot is ingested.
  let(:checkpoint) do
    build(:pm_checkpoint, data_type: 'malware_advisories', version_format: 'v3', purl_type: :npm, sequence: sequence)
  end

  let(:sequence) { 0 }
  let(:reader) do
    instance_double(Gitlab::PackageMetadata::Connector::Archive::TarZstReader, each_entry: [entry])
  end

  let(:entry) do
    instance_double(Gitlab::PackageMetadata::Connector::Archive::TarZstReader::Entry,
      io: StringIO.new(%({"advisory":1}\n)), chunk: 0)
  end

  subject(:data_files) { connector.data_after(checkpoint).to_a }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(checkpoint_path).and_return(true)
    allow(Dir).to receive(:glob).and_call_original
    allow(Dir).to receive(:glob).with('*.tar.zst', base: full_dataset_dir).and_return(shards)
    allow(Dir).to receive(:glob).with('*.tar.zst', base: deltas_dir).and_return(deltas)
    allow(File).to receive(:binread).and_call_original
    shards.each do |shard|
      allow(File).to receive(:binread).with(File.join(full_dataset_dir, shard)).and_return("bytes-#{shard}")
    end
    deltas.each do |delta|
      allow(File).to receive(:binread).with(File.join(deltas_dir, delta)).and_return("bytes-#{delta}")
    end
    allow(Gitlab::PackageMetadata::Connector::Archive::TarZstReader).to receive(:new).and_return(reader)
  end

  context 'with a full-dataset vendor folder' do
    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    it 'reads each local shard and tags files with the snapshot until and base-16 shard index',
      :aggregate_failures do
      expect(data_files).to contain_exactly(
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 0),
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 10)
      )
      expect(data_files).to all(be_a(Gitlab::PackageMetadata::Connector::NdjsonDataFile))
      expect(data_files).to all(be_snapshot)
    end
  end

  context 'when there is no checkpoint.json' do
    before do
      allow(File).to receive(:exist?).with(checkpoint_path).and_return(false)
    end

    it { is_expected.to be_empty }
  end

  context 'when checkpoint.json is corrupt' do
    before do
      stub_file_read(checkpoint_path, content: '{ not json')
    end

    it { is_expected.to be_empty }
  end

  context 'when the snapshot has already been ingested' do
    let(:sequence) { 1_700_000_000 }

    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    it 'yields nothing (checkpoint sequence is at or past the snapshot until)' do
      expect(data_files).to be_empty
    end
  end

  context 'when a newer snapshot has arrived' do
    # Checkpoint is past the previous snapshot but older than the current one, so
    # this is not a first sync yet the newer dataset must still be re-read.
    let(:sequence) { 1_699_999_000 }

    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    it 'reads the newer snapshot shards', :aggregate_failures do
      expect(data_files).to contain_exactly(
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 0),
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 10)
      )
      expect(data_files).to all(be_a(Gitlab::PackageMetadata::Connector::NdjsonDataFile))
      # Resume reads this off the file, so an unmarked shard silently reintroduces
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/628423
      expect(data_files).to all(be_snapshot)
    end
  end

  context 'with a licenses dataset' do
    # Nothing in the reader is dataset specific: the same layout resolves under
    # whichever vendor directory the sync config points at.
    let(:base_uri) { '/vendor/package_metadata/licenses' }
    let(:sync_config) do
      PackageMetadata::SyncConfiguration.new('licenses', :offline, base_uri, 'v3', :gem)
    end

    let(:checkpoint) do
      build(:pm_checkpoint, data_type: 'licenses', version_format: 'v3', purl_type: :gem, sequence: sequence)
    end

    let(:full_dataset_dir) { File.join(base_uri, 'v3', 'rubygem', 'full_dataset') }
    let(:deltas_dir) { File.join(base_uri, 'v3', 'rubygem', 'deltas') }

    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    it 'reads the snapshot from the licenses vendor directory', :aggregate_failures do
      expect(data_files).to contain_exactly(
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 0),
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 10)
      )
      expect(Dir).to have_received(:glob).with('*.tar.zst', base: full_dataset_dir)
    end
  end

  context 'with a purl type whose registry has a different name' do
    # gem data lives under v3/rubygem/, not v3/gem/: the path is built from the
    # registry identifier, not the purl type.
    let(:sync_config) do
      PackageMetadata::SyncConfiguration.new('malware_advisories', :offline, base_uri, 'v3', :gem)
    end

    let(:checkpoint) do
      build(:pm_checkpoint, data_type: 'malware_advisories', version_format: 'v3', purl_type: :gem,
        sequence: sequence)
    end

    let(:full_dataset_dir) { File.join(base_uri, 'v3', 'rubygem', 'full_dataset') }
    let(:deltas_dir) { File.join(base_uri, 'v3', 'rubygem', 'deltas') }

    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    it 'reads shards from the registry_id directory', :aggregate_failures do
      expect(data_files).to contain_exactly(
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 0),
        an_object_having_attributes(sequence: 1_700_000_000, chunk: 10)
      )
      expect(Dir).to have_received(:glob).with('*.tar.zst', base: full_dataset_dir)
    end
  end

  context 'when resuming an interrupted first sync' do
    # The marker keeps first_sync? true; the checkpoint already sits at this
    # snapshot's until with shard 00 ingested, so only shard 0a remains.
    let(:checkpoint) do
      build(:pm_checkpoint, data_type: 'malware_advisories', version_format: 'v3', purl_type: :npm,
        sequence: 1_700_000_000, chunk: 0, full_sync_target_sequence: 1_700_000_000)
    end

    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    it 'skips shards at or below the checkpoint chunk and does not re-read them', :aggregate_failures do
      expect(data_files.map(&:chunk)).to eq([10])
      expect(File).not_to have_received(:binread).with(File.join(full_dataset_dir, '00.tar.zst'))
    end
  end

  describe 'delta archives' do
    # Every delta context starts from an instance that has already ingested the
    # snapshot, which is where the delta chain picks up.
    let(:sequence) { 1_700_000_000 }
    let(:reader) do
      instance_double(Gitlab::PackageMetadata::Connector::Archive::TarZstReader,
        each_entry: [entry, second_entry])
    end

    let(:second_entry) do
      instance_double(Gitlab::PackageMetadata::Connector::Archive::TarZstReader::Entry,
        io: StringIO.new(%({"advisory":2}\n)), chunk: 1)
    end

    before do
      stub_file_read(checkpoint_path, content: '{"until":1700000000}')
    end

    context 'when deltas newer than the checkpoint are on disk' do
      let(:deltas) { ['1700000100.tar.zst', '1700000200.tar.zst'] }

      it 'yields each delta in timestamp order, chunked per archive entry', :aggregate_failures do
        expect(data_files.map { |file| [file.sequence, file.chunk] }).to eq(
          [[1_700_000_100, 0], [1_700_000_100, 1], [1_700_000_200, 0], [1_700_000_200, 1]]
        )
        expect(data_files).to all(be_a(Gitlab::PackageMetadata::Connector::NdjsonDataFile))
      end

      # A delta archive holds flat NDJSON chunks rather than one file. They all carry
      # the archive's sequence, which is what makes the archive a single resumable
      # unit for V3SyncService, and take their chunk from their own entry name.
      it 'gives every file in one archive that archive sequence', :aggregate_failures do
        first_archive = data_files.select { |file| file.sequence == 1_700_000_100 }

        expect(first_archive.size).to eq(2)
        expect(first_archive.map(&:chunk)).to eq([0, 1])
      end

      it 'does not re-read the snapshot' do
        data_files

        expect(File).not_to have_received(:binread).with(File.join(full_dataset_dir, '00.tar.zst'))
      end
    end

    context 'when a delta filename is zero padded' do
      let(:deltas) { ['0001700000100.tar.zst'] }

      # The name is carried through rather than rebuilt from the parsed timestamp,
      # which would look for 1700000100.tar.zst and raise Errno::ENOENT.
      it 'reads the file under its real name', :aggregate_failures do
        expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100])
        expect(File).to have_received(:binread).with(File.join(deltas_dir, '0001700000100.tar.zst'))
      end
    end

    context 'when the deltas on disk are unsorted and partly already ingested' do
      let(:deltas) { ['1700000200.tar.zst', '1699999900.tar.zst', '1700000100.tar.zst'] }

      it 'sorts them and skips the ones at or below the checkpoint' do
        expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100, 1_700_000_200])
      end
    end

    context 'when the deltas hold nothing newer than the checkpoint' do
      let(:deltas) { ['1699999900.tar.zst', '1700000000.tar.zst'] }

      # The snapshot is no newer than the checkpoint either, so the registry is up to
      # date. Re-reading the snapshot here would re-ingest the dataset every cron run.
      it 'yields nothing and leaves the snapshot alone', :aggregate_failures do
        expect(data_files).to be_empty
        expect(File).not_to have_received(:binread).with(File.join(full_dataset_dir, '00.tar.zst'))
      end

      context 'and a newer snapshot has been copied in' do
        # Deltas stay on disk after they are ingested, so every registry sits here
        # once it has synced any delta. A fresher snapshot must still be picked up.
        before do
          stub_file_read(checkpoint_path, content: '{"until":1700000500}')
        end

        it 'falls back to the snapshot', :aggregate_failures do
          expect(data_files.map(&:sequence).uniq).to eq([1_700_000_500])
          # Forced per shard, unlike a delta archive where each entry names its own.
          expect(data_files.map(&:chunk).uniq).to eq([0, 10])
          expect(File).to have_received(:binread).with(File.join(full_dataset_dir, '00.tar.zst'))
        end
      end
    end

    context 'when a delta filename is not a bare timestamp' do
      let(:deltas) { ['partial.tar.zst', '1700000100.tar.zst'] }

      it 'ignores it rather than reading it as sequence zero' do
        expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100])
      end
    end

    context 'when the deltas do not reach back to the checkpoint' do
      # The delta covering the window since the checkpoint is not in the directory.
      # Nothing on disk records where a delta's window begins, so this is
      # indistinguishable from a complete chain: continuity is assumed, not checked.
      let(:sequence) { 1_700_000_500 }
      let(:deltas) { ['1700000900.tar.zst'] }

      it 'ingests them anyway' do
        expect(data_files.map(&:sequence).uniq).to eq([1_700_000_900])
      end
    end

    context 'on a first sync' do
      let(:sequence) { 0 }
      let(:deltas) { ['1700000100.tar.zst'] }

      it 'reads the snapshot and ignores the deltas', :aggregate_failures do
        expect(data_files.map(&:sequence).uniq).to eq([1_700_000_000])
        expect(File).not_to have_received(:binread).with(File.join(deltas_dir, '1700000100.tar.zst'))
      end
    end

    describe 'ordering against the snapshot' do
      context 'when the snapshot lands between two deltas' do
        let(:deltas) { ['1700000100.tar.zst', '1700000300.tar.zst'] }

        before do
          stub_file_read(checkpoint_path, content: '{"until":1700000200}')
        end

        it 'applies all three in timestamp order' do
          expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100, 1_700_000_200, 1_700_000_300])
        end
      end

      context 'when the snapshot is newer than every pending delta' do
        let(:deltas) { ['1700000100.tar.zst', '1700000200.tar.zst'] }

        before do
          stub_file_read(checkpoint_path, content: '{"until":1700000500}')
        end

        it 'applies the deltas first and the snapshot last' do
          expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100, 1_700_000_200, 1_700_000_500])
        end
      end

      context 'when the snapshot is older than the pending delta' do
        let(:deltas) { ['1700000300.tar.zst'] }

        before do
          stub_file_read(checkpoint_path, content: '{"until":1700000100}')
        end

        it 'applies the snapshot first' do
          expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100, 1_700_000_300])
        end
      end

      context 'when a delta carries the same timestamp as the snapshot' do
        let(:deltas) { ['1700000200.tar.zst'] }

        before do
          stub_file_read(checkpoint_path, content: '{"until":1700000200}')
        end

        # Both sides share the sequence, so the chunks tell them apart: the snapshot's
        # two shards force 0 and 10, then the delta's own entries carry 0 and 1.
        it 'applies the snapshot first, leaving the delta as a no-op on top of it' do
          expect(data_files.map(&:chunk)).to eq([0, 0, 10, 10, 0, 1])
        end
      end
    end

    describe 'when the snapshot cannot be read' do
      let(:deltas) { ['1700000100.tar.zst'] }

      context 'and there is no checkpoint.json' do
        # The timeline asks for the snapshot timestamp on every sync, so this is
        # reached without the File.exist? guard the old caller had.
        before do
          allow(File).to receive(:exist?).with(checkpoint_path).and_return(false)
        end

        it 'still applies the pending deltas' do
          expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100])
        end
      end

      context 'and checkpoint.json is corrupt' do
        before do
          stub_file_read(checkpoint_path, content: '{ not json')
        end

        it 'still applies the pending deltas' do
          expect(data_files.map(&:sequence).uniq).to eq([1_700_000_100])
        end
      end
    end
  end
end
