# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Versions::CreateFromArtifactWorker, feature_category: :continuous_delivery do
  let_it_be(:project) { create(:project) }

  let(:source_ref) { 'registry.example.com/group/project/web' }
  let(:image) { "#{source_ref}:latest" }
  let(:data) do
    { project_id: project.id, image: image, repository: source_ref, tag: 'latest', digest: 'sha256:abc' }
  end

  let(:event) { ContainerRegistry::ImagePushedEvent.new(data: data) }

  describe '#handle_event' do
    it_behaves_like 'subscribes to event'

    it 'delegates to CreateFromArtifactService with the event payload' do
      expect_next_instance_of(
        ::Cd::Versions::CreateFromArtifactService,
        image: image, source_ref: source_ref, organization_id: project.organization_id,
        tag: 'latest', digest: 'sha256:abc'
      ) do |service|
        expect(service).to receive(:execute)
      end

      consume_event(subscriber: described_class, event: event)
    end

    it 'does not call the service when the project no longer exists' do
      event.data[:project_id] = non_existing_record_id

      expect(::Cd::Versions::CreateFromArtifactService).not_to receive(:new)

      consume_event(subscriber: described_class, event: event)
    end
  end

  describe '.dispatch?' do
    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_native_deploy: false)
      end

      it 'returns false' do
        expect(described_class.dispatch?(event)).to be(false)
      end
    end

    context 'when the feature flag is enabled' do
      it 'returns true when tag and digest are present' do
        expect(described_class.dispatch?(event)).to be(true)
      end

      it 'returns false when the tag is missing' do
        event.data.delete(:tag)

        expect(described_class.dispatch?(event)).to be(false)
      end

      it 'returns false when the digest is missing' do
        event.data.delete(:digest)

        expect(described_class.dispatch?(event)).to be(false)
      end

      it 'returns false when the repository is missing' do
        event.data.delete(:repository)

        expect(described_class.dispatch?(event)).to be(false)
      end

      it 'returns false for an unrelated event type' do
        expect(described_class.dispatch?(double)).to be(false)
      end
    end
  end
end
