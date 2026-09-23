# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::Exports::PartsLooseForeignKeyCleanerService,
  feature_category: :vulnerability_management do
  let_it_be(:organization) { create(:organization) }

  let(:schema) { SecApplicationRecord.connection.current_schema }

  let(:loose_fk_definition) do
    ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(
      'vulnerability_export_parts',
      'organizations',
      {
        column: 'organization_id',
        on_delete: :async_delete,
        gitlab_schema: :gitlab_sec
      }
    )
  end

  let(:deleted_records) do
    [
      LooseForeignKeys::DeletedRecord.new(
        fully_qualified_table_name: "#{schema}.organizations",
        primary_key_value: organization.id
      )
    ]
  end

  let!(:part) { create(:vulnerability_export_part, :with_csv_file, organization: organization) }

  subject(:cleaner_service) do
    described_class.new(
      loose_foreign_key_definition: loose_fk_definition,
      connection: SecApplicationRecord.connection,
      deleted_parent_records: deleted_records)
  end

  describe '#execute' do
    it 'removes the parts and the uploads they own', :sidekiq_inline do
      part_uploads = Upload.for_model_type_and_id(Vulnerabilities::Export::Part, part.id)

      expect { cleaner_service.execute }
        .to change { Vulnerabilities::Export::Part.exists?(part.id) }.from(true).to(false)
        .and change { part_uploads.count }.from(1).to(0)
    end

    it 'returns the number of affected rows and the table name' do
      expect(cleaner_service.execute).to eq(affected_rows: 1, table: 'vulnerability_export_parts')
    end

    it 'reports the deletion as an async delete to the modification tracker' do
      expect(cleaner_service.async_delete?).to be(true)
    end

    it 'does not remove parts belonging to other organizations' do
      other_part = create(:vulnerability_export_part)

      cleaner_service.execute

      expect(Vulnerabilities::Export::Part.exists?(other_part.id)).to be(true)
    end

    context 'when there are no matching parts' do
      let(:deleted_records) do
        [
          LooseForeignKeys::DeletedRecord.new(
            fully_qualified_table_name: "#{schema}.organizations",
            primary_key_value: non_existing_record_id
          )
        ]
      end

      it 'reports no affected rows' do
        expect(cleaner_service.execute).to eq(affected_rows: 0, table: 'vulnerability_export_parts')
      end
    end
  end
end
