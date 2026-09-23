# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::VerificationStateBackfillService, :geo, feature_category: :geo_replication do
  include EE::GeoHelpers

  shared_examples_for 'verification state separate table backfill' do |model|
    let(:verification_state_class) { model.verification_state_table_class }
    let(:verifiables) { create_list(factory_name(model), 3) }
    let(:verification_state_model_key) { model.verification_state_model_key }

    subject(:job) { described_class.new(model, batch_size: 1000) }

    before do
      stub_primary_node
    end

    describe '#execute' do
      context 'when verifiables are missing verification state records' do
        before do
          verification_state_class.where(verification_state_model_key => verifiables).delete_all
        end

        it 'creates verification state records' do
          expect { job.execute }.to change { verification_state_class.count }.from(0).to(3)
        end

        it 'avoids N+1 queries' do
          # create 3 records
          action = ActiveRecord::QueryRecorder.new { job.execute }

          verification_state_class.first.destroy!

          # create 1 record
          control = ActiveRecord::QueryRecorder.new { job.execute }

          expect(action.count).to eq(control.count)
        end
      end

      context 'when some resources become not-verifiable' do
        before do
          all_except_one = verifiables.map(&:id).last(2)
          stubbed_relation = model.primary_key_in(all_except_one)
          allow(model).to receive(:verifiables).and_return(stubbed_relation)
        end

        it 'deletes the verification state record' do
          expect { job.execute }.to change { verification_state_class.count }.from(3).to(2)
        end
      end
    end
  end

  # Models with a separate verification table
  models = Gitlab::Geo.verification_enabled_replicator_classes.map(&:model).select(&:separate_verification_state_table?)

  models.each do |model|
    context "for #{model}" do
      it_behaves_like 'verification state separate table backfill', model
    end
  end

  # The batch insert is all-or-nothing, so a single group-owned upload used to
  # abort verification state creation for its whole batch range.
  context 'for Geo::BulkImportExportUploadUpload owned by a group' do
    let(:model) { Geo::BulkImportExportUploadUpload }
    let(:verification_state_class) { model.verification_state_table_class }
    let_it_be(:group) { create(:group) }

    let_it_be(:primary) { create(:geo_node, :primary) }

    let!(:group_owned) { create(:geo_bulk_import_export_upload_upload, group: group) }
    let!(:project_owned) { create(:geo_bulk_import_export_upload_upload) }

    before do
      stub_primary_node
      stub_current_geo_node(primary)
      verification_state_class.delete_all
    end

    it 'creates verification state records for group-owned and project-owned uploads' do
      expect { described_class.new(model, batch_size: 1000).execute }
        .to change { verification_state_class.count }.from(0).to(2)

      state = verification_state_class.find_by(bulk_import_export_upload_upload_id: group_owned.id)

      expect(state.namespace_id).to eq(group.id)
      expect(state.project_id).to be_nil
    end
  end
end
