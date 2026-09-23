# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Scans::IngestReportsWorker, feature_category: :vulnerability_management do
  let(:pipeline) { create(:ci_pipeline) }
  let(:job) { create(:ci_build, :sast, pipeline: pipeline, status: 'success') }
  let(:event) { ::Ci::JobSecurityScanCompletedEvent.new(data: { job_id: job.id }) }

  subject(:handle_event) { consume_event(subscriber: described_class, event: event) }

  before do
    allow(::Security::Scans::IngestReportsService).to receive(:execute)
  end

  it_behaves_like 'subscribes to event'

  describe 'deferring on database health' do
    it 'watches the vulnerability_occurrences table on the sec database' do
      expect(described_class.database_health_check_attrs).to include(
        gitlab_schema: :gitlab_sec,
        tables: ['vulnerability_occurrences'],
        delay_by: 1.minute
      )
    end
  end

  describe '.handle_event' do
    it 'handle_event calls service' do
      handle_event

      expect(::Security::Scans::IngestReportsService).to have_received(:execute).with(pipeline)
    end
  end
end
