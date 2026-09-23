# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ProcessOrganizationTransferEventWorker,
  feature_category: :vulnerability_management, type: :job do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: new_organization) }
  let_it_be(:subgroup) { create(:group, parent: group, organization: new_organization) }
  let_it_be(:project) { create(:project, :with_vulnerability, group: group) }
  let_it_be(:subgroup_project) { create(:project, :with_vulnerability, group: subgroup) }
  let_it_be(:project_without_vulnerabilities) { create(:project, group: group) }

  let(:event) do
    ::Organizations::GroupTransferredEvent.new(data: {
      group_id: group.id,
      old_organization_id: old_organization.id,
      new_organization_id: new_organization.id
    })
  end

  before do
    stub_feature_flags(reindex_vulnerabilities_on_organization_transfer: true)
    stub_ee_application_setting(elasticsearch_indexing: true, elasticsearch_search: true)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :always

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  context 'when the transferred group tree has projects with vulnerabilities', :sidekiq_inline do
    it_behaves_like 'subscribes to event'

    it 'enqueues a reindex job for each project in the group tree that has vulnerabilities' do
      expect(Vulnerabilities::ReindexProjectVulnerabilitiesWorker).to receive(:bulk_perform_async).with(
        match_array([[project.id], [subgroup_project.id]])
      )

      use_event
    end
  end

  context 'when the group no longer exists' do
    let(:event) do
      ::Organizations::GroupTransferredEvent.new(data: {
        group_id: non_existing_record_id,
        old_organization_id: old_organization.id,
        new_organization_id: new_organization.id
      })
    end

    it 'does not enqueue any reindex jobs' do
      expect(Vulnerabilities::ReindexProjectVulnerabilitiesWorker).not_to receive(:bulk_perform_async)

      use_event
    end
  end

  describe '.dispatch?' do
    let(:other_group) { create(:group, organization: new_organization) }

    let(:sibling_event) do
      ::Organizations::GroupTransferredEvent.new(data: {
        group_id: other_group.id,
        old_organization_id: old_organization.id,
        new_organization_id: new_organization.id
      })
    end

    # Subscription#consume_events evaluates the condition once per event rather than once per
    # batch, so a transfer publishing one event per group repeats this lookup without the memo.
    # Counted in SQL because `find_by_id` is an ActiveRecord dynamic finder: it is redefined on
    # the singleton after its first call, so a message expectation only ever sees that call.
    it 'looks the organization up once for a batch of events sharing an organization', :request_store do
      recorder = ActiveRecord::QueryRecorder.new do
        Gitlab::EventStore.publish_group([event, sibling_event])
      end

      organization_lookups = recorder.log.count { |query| query.include?('FROM "organizations"') }

      expect(organization_lookups).to eq(1)
    end
  end

  # Deployment safety: while the flag is off, publishing the event must not enqueue this new worker,
  # so a rolling deploy cannot schedule it before every Sidekiq node has the class.
  context 'when the feature flag is disabled', :sidekiq_inline do
    before do
      stub_feature_flags(reindex_vulnerabilities_on_organization_transfer: false)
    end

    it_behaves_like 'ignores the published event'

    # This is the live path while the flag is off: TopLevelGroupService publishes through
    # publish_group, every event is filtered out, and the subscription reaches
    # bulk_perform_async with an empty list.
    it 'enqueues nothing when a whole published batch is filtered out' do
      expect(Vulnerabilities::ReindexProjectVulnerabilitiesWorker).not_to receive(:bulk_perform_async)

      expect { Gitlab::EventStore.publish_group([event, event]) }.not_to raise_error
    end
  end

  context 'when advanced vulnerability management is not allowed' do
    before do
      stub_ee_application_setting(elasticsearch_indexing: false)
    end

    it 'bails before traversing the tree and does not enqueue any reindex jobs' do
      expect(Vulnerabilities::ReindexProjectVulnerabilitiesWorker).not_to receive(:bulk_perform_async)

      use_event
    end
  end

  context 'when re-indexing the whole transferred tree', :elastic_delete_by_query, :sidekiq_inline do
    let_it_be(:source_organization) { create(:organization) }
    let_it_be(:target_organization) { create(:organization) }

    let_it_be_with_reload(:transferred_group) { create(:group, organization: source_organization) }
    let_it_be_with_reload(:subgroup) { create(:group, parent: transferred_group, organization: source_organization) }
    let_it_be_with_reload(:direct_project) do
      create(:project, group: transferred_group, organization: source_organization)
    end

    let_it_be_with_reload(:subgroup_project) { create(:project, group: subgroup, organization: source_organization) }

    # A separate top-level group that is NOT transferred; its vulnerability must stay in the source org.
    let_it_be_with_reload(:other_group) { create(:group, organization: source_organization) }
    let_it_be(:other_project) { create(:project, group: other_group, organization: source_organization) }

    let_it_be(:direct_vuln) do
      create(:vulnerability, :with_read, severity: :critical, report_type: :sast, state: :detected,
        project: direct_project)
    end

    let_it_be(:subgroup_vuln) do
      create(:vulnerability, :with_read, severity: :high, report_type: :sast, state: :detected,
        project: subgroup_project)
    end

    let_it_be(:other_vuln) do
      create(:vulnerability, :with_read, severity: :critical, report_type: :sast, state: :detected,
        project: other_project)
    end

    let(:event) do
      ::Organizations::GroupTransferredEvent.new(data: {
        group_id: transferred_group.id,
        old_organization_id: source_organization.id,
        new_organization_id: target_organization.id
      })
    end

    before do
      [direct_project, subgroup_project, other_project].each do |project|
        project.project_setting.update!(has_vulnerabilities: true)
      end
      stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
      set_elasticsearch_migration_to(:backfill_organization_id_in_vulnerabilities)
      Elastic::ProcessBookkeepingService.track!(direct_vuln, subgroup_vuln, other_vuln)
      ensure_elasticsearch_index!
    end

    def count(organization, severity)
      ::Search::AdvancedFinders::Security::Vulnerability::CountBySeverityFinder
        .new(organization, {})
        .execute
        .dig(severity, 'count').to_i
    end

    # The ConfirmService path delivers this event twice: once when TopLevelGroupService moves the
    # root row, and again when ActivateService moves the descendants via GroupsService.
    it 'converges across both deliveries', :aggregate_failures do
      # 1. ConfirmService moves only the root group row, then publishes.
      transferred_group.update_column(:organization_id, target_organization.id)

      consume_event(subscriber: described_class, event: event)
      ensure_elasticsearch_index!

      # The project directly under the root is already correct. The subgroup project cannot be
      # until its own namespace moves, because organization_id is read from the direct parent.
      expect(count(target_organization, 'critical')).to eq(1) # direct
      expect(count(target_organization, 'high')).to eq(0)

      # 2. ActivateService moves the descendants and the same event is published again.
      [subgroup, direct_project, subgroup_project].each do |record|
        record.update_column(:organization_id, target_organization.id)
      end

      consume_event(subscriber: described_class, event: event)
      ensure_elasticsearch_index!

      expect(count(target_organization, 'critical')).to eq(1) # direct
      expect(count(target_organization, 'high')).to eq(1)     # subgroup descendant
      expect(count(source_organization, 'critical')).to eq(1) # untransferred group is untouched
      expect(count(source_organization, 'high')).to eq(0)
    end

    it 'reindexes descendants too and leaves untransferred projects untouched', :aggregate_failures do
      expect(count(source_organization, 'critical')).to eq(2) # direct + other
      expect(count(source_organization, 'high')).to eq(1)     # subgroup
      expect(count(target_organization, 'critical')).to eq(0)

      # Mirror GroupsService updating organization_id across the whole transferred tree.
      [transferred_group, subgroup, direct_project, subgroup_project].each do |record|
        record.update_column(:organization_id, target_organization.id)
      end

      consume_event(subscriber: described_class, event: event)
      ensure_elasticsearch_index!

      # Transferred tree (direct + subgroup) moved to the target org...
      expect(count(target_organization, 'critical')).to eq(1) # direct
      expect(count(target_organization, 'high')).to eq(1)     # subgroup descendant
      # ...while the untransferred group's vulnerability stays in the source org.
      expect(count(source_organization, 'critical')).to eq(1) # other only
      expect(count(source_organization, 'high')).to eq(0)     # subgroup moved out
    end
  end
end
