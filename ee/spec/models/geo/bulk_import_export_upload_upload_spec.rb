# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::BulkImportExportUploadUpload, feature_category: :geo_replication do
  include ::EE::GeoHelpers

  it { expect(described_class.table_name).to eq('bulk_import_export_upload_uploads') }
  it { expect(described_class.primary_key).to eq('id') }
  it { expect(described_class.superclass).to eq(::Upload) }

  describe 'Geo replication' do
    describe 'associations' do
      it 'has one verification state table class' do
        is_expected
          .to have_one(:bulk_import_export_upload_upload_state)
          .class_name('Geo::BulkImportExportUploadUploadState')
          .inverse_of(:bulk_import_export_upload_upload)
          .autosave(false)
      end
    end

    include_examples 'a verifiable model for verification state' do
      # The factory creates the record via Upload, which may trigger
      # save_partition_verification_details and create the state row.
      # The shared example expects save! to create the state row
      # (count change by 1), so we delete any pre-existing state row
      # and reload the record to clear the cached association.
      let(:verifiable_model_record) do
        record = create(:geo_bulk_import_export_upload_upload)
        described_class.verification_state_table_class.where(bulk_import_export_upload_upload_id: record.id).delete_all
        record.reload
      end

      let(:unverifiable_model_record) do
        record = create(:geo_bulk_import_export_upload_upload, :remote_store)
        described_class.verification_state_table_class.where(bulk_import_export_upload_upload_id: record.id).delete_all
        record.reload
      end
    end

    describe 'group-owned uploads' do
      let_it_be(:group) { create(:group) }
      let_it_be(:primary) { create(:geo_node, :primary) }

      let(:state_class) { described_class.verification_state_table_class }

      let(:group_owned) do
        record = create(:geo_bulk_import_export_upload_upload, group: group)
        state_class.where(bulk_import_export_upload_upload_id: record.id).delete_all
        record.reload
      end

      before do
        stub_current_geo_node(primary)
        stub_dummy_verification_feature_flag(replicator_class: described_class.replicator_class.name)
      end

      describe '.create_verification_details_for' do
        it 'creates a verification state record owned by the namespace' do
          expect { described_class.create_verification_details_for([group_owned.id]) }
            .to change { state_class.count }.by(1)

          state = state_class.find_by(bulk_import_export_upload_upload_id: group_owned.id)

          expect(state.namespace_id).to eq(group.id)
          expect(state.project_id).to be_nil
        end

        it 'creates records for a batch mixing group-owned and project-owned uploads' do
          project_owned = create(:geo_bulk_import_export_upload_upload)
          state_class.delete_all

          expect { described_class.create_verification_details_for([group_owned.id, project_owned.id]) }
            .to change { state_class.count }.by(2)
        end
      end

      describe '#save_verification_details' do
        it 'persists the verification state' do
          expect { group_owned.save_verification_details }.to change { state_class.count }.by(1)

          expect(state_class.find_by(bulk_import_export_upload_upload_id: group_owned.id).namespace_id)
            .to eq(group.id)
        end
      end
    end

    describe 'replication/verification' do
      let_it_be(:group_1, freeze: true) { create(:group, organization: create(:organization)) }
      let_it_be(:group_2, freeze: true) { create(:group, organization: create(:organization)) }
      let_it_be(:nested_group_1, freeze: true) { create(:group, parent: group_1) }
      let_it_be(:project_1, freeze: true) { create(:project, group: group_1) }
      let_it_be(:project_2, freeze: true) { create(:project, group: nested_group_1) }
      let_it_be(:project_3, freeze: true) { create(:project, group: group_2) }

      let!(:first_replicable_and_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, project: project_1)
      end

      let!(:second_replicable_and_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, project: project_2)
      end

      let!(:third_replicable_on_object_storage_and_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, :remote_store, project: project_1)
      end

      let!(:last_replicable_and_not_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, project: project_3)
      end

      include_examples 'Geo Framework selective sync behavior'
    end

    describe 'replication/verification of group-owned uploads' do
      let_it_be(:group_1, freeze: true) { create(:group, organization: create(:organization)) }
      let_it_be(:group_2, freeze: true) { create(:group, organization: create(:organization)) }
      let_it_be(:nested_group_1, freeze: true) { create(:group, parent: group_1) }

      let!(:first_replicable_and_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, group: group_1)
      end

      let!(:second_replicable_and_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, group: nested_group_1)
      end

      let!(:third_replicable_on_object_storage_and_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, :remote_store, group: group_1)
      end

      let!(:last_replicable_and_not_in_selective_sync) do
        create(:geo_bulk_import_export_upload_upload, group: group_2)
      end

      include_examples 'Geo Framework selective sync behavior'
    end
  end
end
