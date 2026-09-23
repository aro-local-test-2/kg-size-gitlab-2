# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::InventoryFilters::UpdateTraversalIdsService, feature_category: :security_asset_inventories do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:other_group) { create(:group) }

  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:other_project) { create(:project, group: other_group) }
  let_it_be(:untouched_project) { create(:project, group: other_group) }

  let_it_be_with_reload(:inventory_filter) { create(:security_inventory_filters, project: project) }
  let_it_be_with_reload(:other_inventory_filter) { create(:security_inventory_filters, project: other_project) }

  let_it_be_with_reload(:subgroup_inventory_filter) do
    create(:security_inventory_filters, project: subgroup_project)
  end

  let_it_be_with_reload(:untouched_inventory_filter) do
    create(:security_inventory_filters, project: untouched_project)
  end

  let(:stale_traversal_ids) { [non_existing_record_id] }
  let(:all_filters) do
    [inventory_filter, subgroup_inventory_filter, other_inventory_filter, untouched_inventory_filter]
  end

  subject(:execute) { described_class.execute(project_ids) }

  before do
    Security::InventoryFilter.id_in(all_filters.map(&:id)).update_all(traversal_ids: stale_traversal_ids)
  end

  describe '.execute' do
    context 'when project_ids is blank' do
      it 'does not update any records', :aggregate_failures do
        expect { described_class.execute([]) }.not_to change { inventory_filter.reload.traversal_ids }
        expect { described_class.execute(nil) }.not_to change { inventory_filter.reload.traversal_ids }
      end
    end

    context 'when project ids span multiple namespaces' do
      let(:project_ids) { [project.id, subgroup_project.id, other_project.id] }

      it 'updates each record with its own namespace traversal ids', :aggregate_failures do
        execute

        expect(inventory_filter.reload.traversal_ids).to eq(group.traversal_ids)
        expect(other_inventory_filter.reload.traversal_ids).to eq(other_group.traversal_ids)
        expect(untouched_inventory_filter.reload.traversal_ids).to eq(stale_traversal_ids)
      end

      it 'writes the direct namespace traversal ids for a nested project', :aggregate_failures do
        execute

        expect(subgroup_inventory_filter.reload.traversal_ids).to match_array([group.id, subgroup.id])
        expect(Security::InventoryFilter.by_traversal_ids(subgroup.traversal_ids))
          .to contain_exactly(subgroup_inventory_filter)
        expect(Security::InventoryFilter.within(group.traversal_ids))
          .to contain_exactly(inventory_filter, subgroup_inventory_filter)
      end
    end

    context 'when the project ids exceed the batch size' do
      let(:project_ids) { [project.id, subgroup_project.id] }

      before do
        stub_const("#{described_class}::PROJECT_BATCH_SIZE", 1)
      end

      it 'updates every record', :aggregate_failures do
        execute

        expect(inventory_filter.reload.traversal_ids).to eq(group.traversal_ids)
        expect(subgroup_inventory_filter.reload.traversal_ids).to eq(subgroup.traversal_ids)
      end
    end

    context 'when a project has no inventory filter record' do
      let_it_be(:project_without_filter) { create(:project, group: group) }

      let(:project_ids) { [project_without_filter.id] }

      it 'does not raise' do
        expect { execute }.not_to raise_error
      end
    end
  end
end
