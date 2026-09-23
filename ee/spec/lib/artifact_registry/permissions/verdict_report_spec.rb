# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Permissions::VerdictReport, feature_category: :artifact_registry do
  let(:slug) { 'my-group' }
  let(:lifetime) { described_class::LIFETIME }

  before do
    allow(Gitlab::ErrorTracking).to receive(:track_exception)
  end

  def absent(read: :repository, slug: self.slug)
    ArtifactRegistry::Permissions::Verdicts.absent(scope: :repository, read: read, slug: slug)
  end

  def incomplete(read: :repository, slug: self.slug)
    ArtifactRegistry::Permissions::Verdicts.new(
      { 'read_repository' => true, 'update_repository' => false }, scope: :repository, read: read, slug: slug
    )
  end

  describe '.absent' do
    it 'tracks one exception naming the read and the slug for a repeated absence', :aggregate_failures do
      described_class.absent(absent)
      described_class.absent(absent)

      expect(Gitlab::ErrorTracking).to have_received(:track_exception)
        .with(instance_of(described_class::AbsentError), { read: :repository, slug: slug }).once
    end

    it 'reports again for the same absence on another read' do
      described_class.absent(absent)
      described_class.absent(absent(read: :repositories))

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(described_class::AbsentError), { read: :repositories, slug: slug }
      ).once
    end

    it 'reports again for the same absence on another slug' do
      described_class.absent(absent)
      described_class.absent(absent(slug: 'other-group'))

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(described_class::AbsentError), { read: :repository, slug: 'other-group' }
      ).once
    end

    it 'reports again once the memo lifetime has elapsed, and not before', :aggregate_failures do
      described_class.absent(absent)

      travel_to(lifetime.from_now - 1.minute) { described_class.absent(absent) }

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).once

      travel_to(lifetime.from_now + 1.minute) { described_class.absent(absent) }

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).twice
    end

    it 'returns nil whether or not it reports', :aggregate_failures do
      expect(described_class.absent(absent)).to be_nil
      expect(described_class.absent(absent)).to be_nil
    end
  end

  describe '.drift' do
    it 'tracks one exception naming the read, the slug, and the missing actions for a repeated drift',
      :aggregate_failures do
      described_class.drift(incomplete)
      described_class.drift(incomplete)

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(described_class::DriftError),
        {
          read: :repository,
          slug: slug,
          missing_actions: %w[
            delete_repository create_repository_upstream update_repository_upstream delete_repository_upstream
            read_artifact create_artifact delete_artifact
          ]
        }
      ).once
    end

    it 'reports again for the same drift on another read or slug' do
      described_class.drift(incomplete)
      described_class.drift(incomplete(read: :repositories))
      described_class.drift(incomplete(slug: 'other-group'))

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).exactly(3).times
    end

    it 'reports again once the memo lifetime has elapsed' do
      described_class.drift(incomplete)

      travel_to(lifetime.from_now + 1.minute) { described_class.drift(incomplete) }

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).twice
    end

    it 'does not suppress an absence on the same read and slug, nor is suppressed by one' do
      described_class.absent(absent)
      described_class.drift(incomplete)

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).twice
    end
  end

  describe '.defect' do
    it 'tracks one exception naming the scope for a repeated defect' do
      described_class.defect(scope: 'ArtifactRegistryRepository')
      described_class.defect(scope: 'ArtifactRegistryRepository')

      expect(Gitlab::ErrorTracking).to have_received(:track_exception)
        .with(instance_of(described_class::DefectError), { scope: 'ArtifactRegistryRepository' }).once
    end

    it 'reports again for a defect on another scope' do
      described_class.defect(scope: 'ArtifactRegistryRepository')
      described_class.defect(scope: 'ArtifactRegistryRepositoryConnection')

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        instance_of(described_class::DefectError), { scope: 'ArtifactRegistryRepositoryConnection' }
      ).once
    end

    it 'reports again once the memo lifetime has elapsed' do
      described_class.defect(scope: 'ArtifactRegistryRepository')

      travel_to(lifetime.from_now + 1.minute) { described_class.defect(scope: 'ArtifactRegistryRepository') }

      expect(Gitlab::ErrorTracking).to have_received(:track_exception).twice
    end
  end
end
