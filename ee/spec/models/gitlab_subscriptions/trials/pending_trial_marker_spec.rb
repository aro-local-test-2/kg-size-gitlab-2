# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Trials::PendingTrialMarker, :use_clean_rails_memory_store_caching, feature_category: :acquisition do
  let(:namespace_id) { non_existing_record_id }

  describe '.set' do
    it 'writes a marker to the cache with a 5-minute TTL' do
      described_class.set(namespace_id)

      expect(described_class.active?(namespace_id)).to be(true)
    end
  end

  describe '.active?' do
    it 'returns false when no marker has been set' do
      expect(described_class.active?(namespace_id)).to be(false)
    end

    it 'returns true after a marker is set' do
      described_class.set(namespace_id)

      expect(described_class.active?(namespace_id)).to be(true)
    end

    context 'with TTL behavior' do
      it 'returns false after the TTL has elapsed' do
        described_class.set(namespace_id)

        travel_to(GitlabSubscriptions::Trials::PendingTrialMarker::CACHE_TTL.from_now + 1.second) do
          expect(described_class.active?(namespace_id)).to be(false)
        end
      end
    end
  end
end
