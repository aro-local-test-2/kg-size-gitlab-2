# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CheckpointHeader, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow) }

  subject(:header) { build(:duo_workflows_checkpoint_header, workflow: workflow) }

  describe 'associations' do
    it { is_expected.to belong_to(:workflow).class_name('Ai::DuoWorkflows::Workflow') }
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to belong_to(:namespace).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:workflow) }
    it { is_expected.to validate_presence_of(:thread_ts) }
  end

  describe '.for_checkpoint_ns' do
    # Matched on thread_ts, not on the records themselves: the composite
    # [id, workflow_created_at] primary key makes ActiveRecord's `==` compare the
    # timestamp too, and the in-memory value carries sub-microsecond precision that
    # Postgres truncates, so a record never equals its own reloaded row.
    let_it_be(:top_level) { create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-top') }
    let_it_be(:nested) do
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-nested',
        checkpoint_ns: 'research_agent:0f8ba4c5')
    end

    it 'returns only headers in the given lineage' do
      expect(described_class.for_checkpoint_ns('research_agent:0f8ba4c5').map(&:thread_ts))
        .to contain_exactly('ts-nested')
    end

    it 'treats a blank namespace as the top-level lineage' do
      expect(described_class.for_checkpoint_ns('').map(&:thread_ts)).to contain_exactly('ts-top')
      expect(described_class.for_checkpoint_ns(nil).map(&:thread_ts)).to contain_exactly('ts-top')
    end
  end

  describe 'normalizing checkpoint_ns' do
    it 'stores a blank namespace as nil', :aggregate_failures do
      header = create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-blank',
        checkpoint_ns: '')

      expect(header.checkpoint_ns).to be_nil
      expect(described_class.for_checkpoint_ns(nil).map(&:thread_ts)).to include('ts-blank')
    end

    it 'leaves a namespace untouched' do
      header = create(:duo_workflows_checkpoint_header, workflow: workflow,
        checkpoint_ns: 'research_agent:0f8ba4c5')

      expect(header.checkpoint_ns).to eq('research_agent:0f8ba4c5')
    end

    it 'normalizes on the bulk insert path the shadow write uses' do
      now = Time.current
      header = build(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-bulk',
        checkpoint_ns: '', created_at: now, updated_at: now)

      described_class.bulk_insert!([header])

      expect(described_class.find_by(thread_ts: 'ts-bulk').checkpoint_ns).to be_nil
    end
  end

  describe '.in_reverse_checkpoint_order' do
    it 'orders by thread_ts descending, so the first row is the newest checkpoint' do
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2')
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-3')
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1')

      expect(described_class.in_reverse_checkpoint_order.map(&:thread_ts)).to eq(%w[ts-3 ts-2 ts-1])
    end
  end

  describe '.for_current_thread' do
    it 'orders the group by thread_ts, so the last row is the newest checkpoint' do
      # Insert the newest thread_ts first: a higher id must not count as newer.
      create(:duo_workflows_checkpoint_header, workflow: workflow, current_thread: 1, thread_ts: 'ts-3')
      create(:duo_workflows_checkpoint_header, workflow: workflow, current_thread: 1, thread_ts: 'ts-2')
      create(:duo_workflows_checkpoint_header, workflow: workflow, current_thread: 0, thread_ts: 'ts-1')

      # Assert on thread_ts, not the records: the composite primary key makes
      # object equality depend on workflow_created_at precision across reloads.
      expect(described_class.for_current_thread(1).map(&:thread_ts)).to eq(%w[ts-2 ts-3])
    end
  end

  describe '.latest_per_workflow' do
    let_it_be(:other_workflow) { create(:duo_workflows_workflow) }

    it 'returns one newest header per workflow, breaking thread_ts ties by id', :aggregate_failures do
      # Insert the newest thread_ts first: a higher id must not count as newer.
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2')
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1')
      # A re-sent checkpoint appends a second row for the same thread_ts.
      resent = create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2')
      create(:duo_workflows_checkpoint_header, workflow: other_workflow, thread_ts: 'ts-0')

      latest = described_class.latest_per_workflow.index_by(&:workflow_id)

      expect(latest.keys).to contain_exactly(workflow.id, other_workflow.id)
      expect(latest[workflow.id].thread_ts).to eq('ts-2')
      expect(latest[workflow.id].id.first).to eq(resent.id.first)
      expect(latest[other_workflow.id].thread_ts).to eq('ts-0')
    end
  end

  describe '.earliest_per_workflow' do
    let_it_be(:other_workflow) { create(:duo_workflows_workflow) }

    it 'returns one oldest header per workflow, breaking thread_ts ties by id', :aggregate_failures do
      # Insert the oldest thread_ts last: a lower id must not count as older.
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2')
      first = create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1')
      # A re-sent checkpoint appends a second row for the same thread_ts.
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1')
      create(:duo_workflows_checkpoint_header, workflow: other_workflow, thread_ts: 'ts-0')

      earliest = described_class.earliest_per_workflow.index_by(&:workflow_id)

      expect(earliest.keys).to contain_exactly(workflow.id, other_workflow.id)
      expect(earliest[workflow.id].thread_ts).to eq('ts-1')
      expect(earliest[workflow.id].id.first).to eq(first.id.first)
      expect(earliest[other_workflow.id].thread_ts).to eq('ts-0')
    end
  end

  describe '#to_global_id' do
    let_it_be(:persisted_header) { create(:duo_workflows_checkpoint_header, workflow: workflow) }

    it 'returns a GlobalID with the first id element' do
      gid = persisted_header.to_global_id

      expect(gid).to be_a(GlobalID)
      expect(gid.model_id).to eq(persisted_header.id.first.to_s)
    end

    # Compares the scalar id, not the whole composite key: the in-memory record keeps
    # nanosecond precision and the reloaded one is truncated to microseconds by the
    # column type, so the timestamps differ even for the same row.
    it 'round-trips through GlobalID::Locator, as GraphQL subscription payloads do', :aggregate_failures do
      located = GlobalID::Locator.locate(persisted_header.to_gid_param)

      expect(located).to be_a(described_class)
      expect(located.id.first).to eq(persisted_header.id.first)
    end
  end

  describe 'syncing workflow container' do
    context 'with a project-level workflow' do
      it 'sets project_id from the workflow' do
        header.valid?
        expect(header.project_id).to eq(workflow.project_id)
      end
    end

    context 'with a namespace-level workflow' do
      let_it_be(:workflow) { create(:duo_workflows_workflow, namespace: create(:group)) }

      it 'sets namespace_id from the workflow' do
        header.valid?
        expect(header.namespace_id).to eq(workflow.namespace_id)
      end
    end
  end
end
