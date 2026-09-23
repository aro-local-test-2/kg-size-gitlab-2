# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::NamespaceOrganizationsSyncCronWorker, :click_house,
  feature_category: :value_stream_management do
  it_behaves_like 'an idempotent worker'

  it 'delegates to the sync service' do
    expect_next_instance_of(ClickHouse::DataIngestion::NamespaceOrganizationsSyncService) do |service|
      expect(service).to receive(:execute).and_return(ServiceResponse.success(payload: {}))
    end

    described_class.new.perform
  end

  context 'when ClickHouse is not configured' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:configured?).and_return(false)
    end

    it 'does not run the sync' do
      expect(ClickHouse::DataIngestion::NamespaceOrganizationsSyncService).not_to receive(:new)

      described_class.new.perform
    end
  end
end
