# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::InventoryFilters::UpdateTraversalIdsWorker, feature_category: :security_asset_inventories do
  let(:worker) { described_class.new }
  let(:project_ids) { [1, 2, 3] }
  let(:update_service) { Security::InventoryFilters::UpdateTraversalIdsService }

  subject(:perform) { worker.perform(project_ids) }

  describe '#perform' do
    before do
      allow(update_service).to receive(:execute)
    end

    it 'calls the update service with the project ids' do
      perform

      expect(update_service).to have_received(:execute).with(project_ids)
    end
  end
end
