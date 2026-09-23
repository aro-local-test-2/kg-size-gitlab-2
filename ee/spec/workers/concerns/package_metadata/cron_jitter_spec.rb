# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::CronJitter, feature_category: :software_composition_analysis do
  let(:worker_class) do
    Class.new do
      include PackageMetadata::CronJitter

      def self.name
        'PackageMetadata::TestSyncWorker'
      end
    end
  end

  let(:other_worker_class) do
    Class.new(worker_class) do
      def self.name
        'PackageMetadata::OtherTestSyncWorker'
      end
    end
  end

  let(:worker) { worker_class.new }

  describe '#apply_jitter?' do
    subject(:apply_jitter) { worker.send(:apply_jitter?) }

    context 'when running on GitLab.com' do
      before do
        allow(Gitlab).to receive(:com?).and_return(true)
      end

      it { is_expected.to be(false) }
    end

    context 'when running on a self-managed instance' do
      before do
        allow(Gitlab).to receive(:com?).and_return(false)
      end

      it { is_expected.to be(true) }
    end
  end

  describe '#jitter_offset' do
    subject(:offset) { worker.send(:jitter_offset) }

    before do
      allow(Gitlab::CurrentSettings).to receive(:uuid).and_return('fixed-instance-uuid')
    end

    # Keeps a tick's delayed run from outliving the next tick.
    it 'falls within [0, MAX_JITTER) seconds' do
      expect(offset).to be_between(0, described_class::MAX_JITTER.to_i - 1)
    end

    it 'is derived as SHA256(uuid:class_name) mod MAX_JITTER' do
      expected = Digest::SHA256
        .hexdigest('fixed-instance-uuid:PackageMetadata::TestSyncWorker')
        .to_i(16) % described_class::MAX_JITTER.to_i

      expect(offset).to eq(expected)
    end

    it 'is deterministic for a given instance and worker' do
      expect(offset).to eq(worker_class.new.send(:jitter_offset))
    end

    it 'gives a different instance a different offset' do
      first = offset

      allow(Gitlab::CurrentSettings).to receive(:uuid).and_return('another-instance-uuid')

      expect(worker_class.new.send(:jitter_offset)).not_to eq(first)
    end

    it 'gives another worker on the same instance a different offset' do
      expect(other_worker_class.new.send(:jitter_offset)).not_to eq(offset)
    end

    # Both crons run on the same schedule, so equal offsets would stack the
    # two PDS calls on every tick.
    it 'gives the sync workers that share a cron schedule different offsets' do
      licenses = PackageMetadata::LicensesSyncWorker.new.send(:jitter_offset)
      malware = PackageMetadata::MalwareAdvisoriesSyncWorker.new.send(:jitter_offset)

      expect(licenses).not_to eq(malware)
    end
  end
end
