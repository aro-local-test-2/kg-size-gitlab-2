# frozen_string_literal: true

FactoryBot.define do
  factory :geo_bulk_import_export_upload_upload, class: 'Geo::BulkImportExportUploadUpload' do
    # Upload partition tables are read-only. Data is written through the
    # Upload model to the uploads parent table, and PostgreSQL routes the
    # row to the correct partition by model_type.
    #
    # This factory creates a regular Upload with the appropriate model
    # association, then returns the record from the partition table.
    #
    # A Direct Transfer export is owned by either a project or a group, so pass
    # `group:` for a group-owned upload. It has to reach ExportUpload too, or
    # Upload#ensure_sharding_key reads a blank sharding key.
    transient do
      group { nil }
      project { create(:project) if group.nil? } # rubocop:disable RSpec/FactoryBot/InlineAssociation -- See above
      export_owner { group ? { group: group } : { project: project } }
      export { create(:bulk_import_export, **export_owner) } # rubocop:disable RSpec/FactoryBot/InlineAssociation -- See above
      parent_model { create(:bulk_import_export_upload, export: export, group: group) } # rubocop:disable RSpec/FactoryBot/InlineAssociation -- See above
    end

    initialize_with do
      upload = create(:upload, :with_file, model: parent_model)
      Geo::BulkImportExportUploadUpload.find(upload.id)
    end

    trait :remote_store do
      initialize_with do
        upload = create(:upload, :object_storage, model: parent_model)
        Geo::BulkImportExportUploadUpload.find(upload.id)
      end
    end

    # Verification state is stored in a separate state table
    # (Geo::BulkImportExportUploadUploadState), not on the model itself.
    trait(:verification_succeeded) do
      after(:create) do |instance|
        state = instance.bulk_import_export_upload_upload_state
        state.verification_checksum = 'abc'
        state.verification_state = Geo::BulkImportExportUploadUpload.verification_state_value(:verification_succeeded)
        state.save!
      end
    end

    trait(:verification_failed) do
      after(:create) do |instance|
        state = instance.bulk_import_export_upload_upload_state
        state.verification_failure = 'Could not calculate the checksum'
        state.verification_state = Geo::BulkImportExportUploadUpload.verification_state_value(:verification_failed)
        state.save!
      end
    end

    to_create { |instance| instance } # already persisted via initialize_with
  end
end
