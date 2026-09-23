# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::Concerns::LinkArtifact, feature_category: :duo_agent_platform do
  let(:linking_class) { Class.new { include Ai::DuoWorkflows::Concerns::LinkArtifact } }
  let(:instance) { linking_class.new }

  let(:workflow) { build_stubbed(:duo_workflows_workflow) }
  let(:artifact) { build_stubbed(:merge_request) }

  describe '#link_artifact' do
    subject(:link_artifact) { instance.send(:link_artifact, workflow, artifact, link_type: :source) }

    it 'links the artifact to the workflow via LinkArtifactService' do
      expect_next_instance_of(
        ::Ai::DuoWorkflows::LinkArtifactService,
        workflow: workflow, artifact: artifact, link_type: :source, extra_attributes: {}
      ) do |service|
        expect(service).to receive(:execute)
      end

      link_artifact
    end

    context 'with extra attributes' do
      subject(:link_artifact) do
        instance.send(:link_artifact, workflow, artifact, link_type: :source,
          extra_attributes: { idempotency_key: 'key' })
      end

      it 'passes the attributes to LinkArtifactService' do
        expect_next_instance_of(
          ::Ai::DuoWorkflows::LinkArtifactService,
          workflow: workflow, artifact: artifact, link_type: :source,
          extra_attributes: { idempotency_key: 'key' }
        ) do |service|
          expect(service).to receive(:execute)
        end

        link_artifact
      end
    end

    context 'when workflow is nil' do
      let(:workflow) { nil }

      it 'does not call LinkArtifactService' do
        expect(::Ai::DuoWorkflows::LinkArtifactService).not_to receive(:new)

        link_artifact
      end
    end

    context 'when artifact is nil' do
      let(:artifact) { nil }

      it 'does not call LinkArtifactService' do
        expect(::Ai::DuoWorkflows::LinkArtifactService).not_to receive(:new)

        link_artifact
      end
    end

    context 'when linking fails' do
      let(:error) { StandardError.new('link failed') }

      before do
        allow_next_instance_of(::Ai::DuoWorkflows::LinkArtifactService) do |service|
          allow(service).to receive(:execute).and_raise(error)
        end
      end

      it 'tracks the exception without raising' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id)

        expect { link_artifact }.not_to raise_error
      end
    end

    context 'when the artifact is provided as a block' do
      subject(:link_artifact) { instance.send(:link_artifact, workflow, link_type: :source) { artifact } }

      it 'links the artifact resolved by the block' do
        expect_next_instance_of(
          ::Ai::DuoWorkflows::LinkArtifactService,
          workflow: workflow, artifact: artifact, link_type: :source, extra_attributes: {}
        ) do |service|
          expect(service).to receive(:execute)
        end

        link_artifact
      end

      context 'when the block returns nil' do
        let(:artifact) { nil }

        it 'does not call LinkArtifactService' do
          expect(::Ai::DuoWorkflows::LinkArtifactService).not_to receive(:new)

          link_artifact
        end
      end

      context 'when the block raises' do
        subject(:link_artifact) do
          instance.send(:link_artifact, workflow, link_type: :source) { raise error }
        end

        let(:error) { StandardError.new('artifact resolution failed') }

        it 'tracks the exception without raising' do
          expect(::Ai::DuoWorkflows::LinkArtifactService).not_to receive(:new)
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id)

          expect { link_artifact }.not_to raise_error
        end
      end
    end
  end
end
