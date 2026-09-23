# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillTraversalIdsInSecurityInventoryFilters,
  feature_category: :security_asset_inventories do
  let(:security_inventory_filters) { table(:security_inventory_filters, database: :sec) }
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }

  let(:organization) { organizations.create!(name: 'organization', path: 'organization') }

  let(:sub_batch_size) { 100 }

  let(:migration_instance) do
    described_class.new(
      start_cursor: [security_inventory_filters.minimum(:id)],
      end_cursor: [security_inventory_filters.maximum(:id)],
      batch_table: :security_inventory_filters,
      batch_column: :id,
      sub_batch_size: sub_batch_size,
      pause_ms: 0,
      connection: SecApplicationRecord.connection
    )
  end

  subject(:perform_migration) { migration_instance.perform }

  def create_group(name, parent: nil)
    namespaces.create!(
      name: name, path: name, type: 'Group',
      parent_id: parent&.id, organization_id: organization.id
    ).tap { |group| group.update!(traversal_ids: [*parent&.traversal_ids, group.id]) }
  end

  def create_project(name, group)
    project_namespace = namespaces.create!(
      name: name, path: name, type: 'Project', organization_id: organization.id
    )

    projects.create!(
      name: name, path: name, namespace_id: group.id,
      project_namespace_id: project_namespace.id, organization_id: organization.id
    )
  end

  def create_filter(project_id, traversal_ids)
    security_inventory_filters.create!(
      project_id: project_id,
      project_name: "project-#{project_id}",
      traversal_ids: traversal_ids,
      archived: false
    )
  end

  def stored_traversal_ids
    security_inventory_filters.order(:id).pluck(:id, :traversal_ids)
  end

  describe '#perform' do
    let(:old_parent) { create_group('old-parent') }
    let(:new_parent) { create_group('new-parent') }
    let(:moved_group) { create_group('moved', parent: new_parent) }
    let(:promoted_group) { create_group('promoted') }

    let(:moved_project) { create_project('moved-project', moved_group) }
    let(:promoted_project) { create_project('promoted-project', promoted_group) }
    let(:correct_project) { create_project('correct-project', new_parent) }

    let!(:drifted_filter) { create_filter(moved_project.id, [old_parent.id, moved_group.id]) }
    let!(:promoted_filter) { create_filter(promoted_project.id, [old_parent.id, promoted_group.id]) }
    let!(:correct_filter) { create_filter(correct_project.id, new_parent.traversal_ids) }
    let!(:orphan_filter) { create_filter(non_existing_record_id, [old_parent.id]) }
    let!(:empty_filter) { create_filter(create_project('empty-project', new_parent).id, []) }

    it 'rewrites drifted rows and leaves the rest untouched', :aggregate_failures do
      perform_migration

      expect(drifted_filter.reload.traversal_ids).to eq(moved_group.traversal_ids)
      expect(promoted_filter.reload.traversal_ids).to eq(promoted_group.traversal_ids)
      expect(correct_filter.reload.traversal_ids).to eq(new_parent.traversal_ids)
      expect(orphan_filter.reload.traversal_ids).to eq([old_parent.id])
      expect(empty_filter.reload.traversal_ids).to eq(new_parent.traversal_ids)
    end

    it 'is idempotent' do
      perform_migration

      expect { migration_instance.perform }.not_to change { stored_traversal_ids }
    end

    context 'when the row changes after the job reads it' do
      let(:newer_traversal_ids) { [create_group('newest-parent').id, moved_group.id] }

      before do
        allow(described_class::Project).to receive(:namespace_traversal_ids).and_wrap_original do |original, ids|
          security_inventory_filters
            .where(project_id: moved_project.id)
            .update_all(traversal_ids: newer_traversal_ids)

          original.call(ids)
        end
      end

      it 'keeps the newer value' do
        perform_migration

        expect(drifted_filter.reload.traversal_ids).to eq(newer_traversal_ids)
      end
    end

    context 'when the rows span several sub batches' do
      let(:sub_batch_size) { 2 }

      let!(:extra_filters) do
        Array.new(3) do |index|
          create_filter(create_project("extra-#{index}", moved_group).id, [old_parent.id, moved_group.id])
        end
      end

      it 'rewrites every drifted row across batches', :aggregate_failures do
        perform_migration

        expect(extra_filters.map { |filter| filter.reload.traversal_ids })
          .to all(eq(moved_group.traversal_ids))
        expect(correct_filter.reload.traversal_ids).to eq(new_parent.traversal_ids)
      end
    end

    context 'when the namespace itself has empty traversal_ids' do
      let(:broken_group) do
        namespaces.create!(name: 'broken', path: 'broken', type: 'Group', organization_id: organization.id)
      end

      let(:broken_project) { create_project('broken-project', broken_group) }
      let!(:broken_filter) { create_filter(broken_project.id, [old_parent.id]) }

      it 'overwrites the stored value with the empty namespace value' do
        perform_migration

        expect(broken_filter.reload.traversal_ids).to eq([])
      end
    end
  end
end
