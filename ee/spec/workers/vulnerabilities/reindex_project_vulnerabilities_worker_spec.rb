# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ReindexProjectVulnerabilitiesWorker,
  feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_read, project: project) }

  subject(:perform) { described_class.new.perform(project.id) }

  before do
    stub_ee_application_setting(elasticsearch_indexing: true, elasticsearch_search: true)
  end

  include_examples 'an idempotent worker' do
    let(:job_args) { [project.id] }
  end

  it "re-indexes the project's vulnerability_reads via BulkEsOperationService" do
    expect_next_instance_of(Vulnerabilities::BulkEsOperationService) do |service|
      expect(service).to receive(:execute)
    end

    perform
  end

  context 'when the project no longer exists' do
    it 'does nothing' do
      expect(Vulnerabilities::BulkEsOperationService).not_to receive(:new)

      described_class.new.perform(non_existing_record_id)
    end
  end

  context 'when advanced vulnerability management is not allowed' do
    before do
      stub_ee_application_setting(elasticsearch_indexing: false)
    end

    it 'does nothing' do
      expect(Vulnerabilities::BulkEsOperationService).not_to receive(:new)

      perform
    end
  end
end
