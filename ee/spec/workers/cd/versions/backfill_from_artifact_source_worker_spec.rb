# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Versions::BackfillFromArtifactSourceWorker, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:service) { create(:cd_service, application: application, organization: organization) }
  let_it_be(:artifact_source) { create(:cd_artifact_source, service: service, organization: organization) }

  describe '#perform' do
    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [artifact_source.id] }
    end

    it 'delegates to BackfillFromArtifactSourceService' do
      expect_next_instance_of(::Cd::Versions::BackfillFromArtifactSourceService, artifact_source) do |backfill_service|
        expect(backfill_service).to receive(:execute)
      end

      described_class.new.perform(artifact_source.id)
    end

    it 'does nothing when the artifact source no longer exists' do
      expect(::Cd::Versions::BackfillFromArtifactSourceService).not_to receive(:new)

      expect { described_class.new.perform(non_existing_record_id) }.not_to raise_error
    end
  end
end
