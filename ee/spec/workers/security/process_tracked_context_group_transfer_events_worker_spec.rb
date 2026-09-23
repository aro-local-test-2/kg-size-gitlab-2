# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProcessTrackedContextGroupTransferEventsWorker, feature_category: :vulnerability_management do
  let_it_be(:old_namespace) { create(:group) }
  let_it_be(:new_namespace) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: new_namespace) }
  let_it_be(:untracked_group) { create(:group) }

  let_it_be(:project) { create(:project, namespace: new_namespace) }
  let_it_be(:subgroup_project) { create(:project, namespace: subgroup) }
  let_it_be(:project_without_tracked_contexts) { create(:project, namespace: new_namespace) }
  let_it_be(:untracked_group_project) { create(:project, namespace: untracked_group) }

  let(:group_id) { new_namespace.id }

  let(:event) do
    ::Groups::GroupTransferedEvent.new(data: {
      group_id: group_id,
      old_root_namespace_id: old_namespace.id,
      new_root_namespace_id: new_namespace.id
    })
  end

  before_all do
    # Two contexts on the same project, to ensure we aren't enqueuing duplicate ids
    create_list(:security_project_tracked_context, 2, :tracked, project: project)
    create(:security_project_tracked_context, :tracked, project: subgroup_project)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  it 'has the correct concurrency limit' do
    expect(described_class.get_concurrency_limit).to eq(10)
  end

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  context 'when a group transfer event is published', :sidekiq_inline do
    it_behaves_like 'subscribes to event'

    it 'enqueues a sync job for each project with tracked contexts, including nested subgroups' do
      expect(::Security::SyncTrackedContextTraversalIdsWorker).to receive(:bulk_perform_async).with(
        match_array([[project.id], [subgroup_project.id]])
      )

      use_event
    end
  end

  context 'when no project in the group has tracked contexts' do
    let(:group_id) { untracked_group.id }

    it 'does not enqueue any sync job' do
      expect(::Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:bulk_perform_async)

      use_event
    end
  end

  context 'when the group no longer exists' do
    let(:group_id) { non_existing_record_id }

    it 'does not enqueue any sync job' do
      expect(::Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:bulk_perform_async)

      use_event
    end
  end
end
