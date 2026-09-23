# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::Exports::LooseForeignKeyCleanerService, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project) }

  let(:schema) { SecApplicationRecord.connection.current_schema }

  let(:loose_fk_definition) do
    ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new(
      'vulnerability_exports',
      'projects',
      {
        column: 'project_id',
        on_delete: :async_delete,
        gitlab_schema: :gitlab_sec
      }
    )
  end

  let(:deleted_records) do
    [
      LooseForeignKeys::DeletedRecord.new(
        fully_qualified_table_name: "#{schema}.projects",
        primary_key_value: project.id
      )
    ]
  end

  let!(:export) { create(:vulnerability_export, :with_csv_file, project: project) }

  subject(:cleaner_service) do
    described_class.new(
      loose_foreign_key_definition: loose_fk_definition,
      connection: SecApplicationRecord.connection,
      deleted_parent_records: deleted_records)
  end

  describe '#execute' do
    it 'removes the exports and the uploads they own', :sidekiq_inline do
      export_uploads = Upload.for_model_type_and_id(Vulnerabilities::Export, export.id)

      expect { cleaner_service.execute }
        .to change { Vulnerabilities::Export.exists?(export.id) }.from(true).to(false)
        .and change { export_uploads.count }.from(1).to(0)
    end

    it 'returns the number of affected rows and the table name' do
      expect(cleaner_service.execute).to eq(affected_rows: 1, table: 'vulnerability_exports')
    end

    it 'reports the deletion as an async delete to the modification tracker' do
      expect(cleaner_service.async_delete?).to be(true)
    end

    it 'does not remove exports belonging to other projects' do
      other_export = create(:vulnerability_export)

      cleaner_service.execute

      expect(Vulnerabilities::Export.exists?(other_export.id)).to be(true)
    end

    context 'when a delete_limit is configured' do
      let!(:second_export) { create(:vulnerability_export, :with_csv_file, project: project) }

      before do
        loose_fk_definition.options[:delete_limit] = 1
      end

      it 'only processes up to the limit per call' do
        expect { cleaner_service.execute }.to change { Vulnerabilities::Export.count }.by(-1)
      end
    end

    context 'when there are no matching exports' do
      let(:deleted_records) do
        [
          LooseForeignKeys::DeletedRecord.new(
            fully_qualified_table_name: "#{schema}.projects",
            primary_key_value: non_existing_record_id
          )
        ]
      end

      it 'reports no affected rows' do
        expect(cleaner_service.execute).to eq(affected_rows: 0, table: 'vulnerability_exports')
      end
    end
  end
end
