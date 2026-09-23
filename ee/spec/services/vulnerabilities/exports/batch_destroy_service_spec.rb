# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::Exports::BatchDestroyService, '#execute', feature_category: :vulnerability_management do
  subject(:execute) { described_class.new(exports: vulnerabilities_export).execute }

  let(:vulnerabilities_export) { Vulnerabilities::Export.all }
  let(:export_parts) { Vulnerabilities::Export::Part.all }
  let(:uploads) { Upload }

  let(:vulnerabilities_export_count) { 2 }

  let!(:parts) do
    create_list(:vulnerability_export, vulnerabilities_export_count, :with_csv_file).map do |export|
      create(:vulnerability_export_part, :with_csv_file, vulnerability_export: export)
    end
  end

  it 'deletes vulnerability exports and their parts', :sidekiq_inline do
    expect { execute }
      .to change { vulnerabilities_export.count }.from(vulnerabilities_export_count).to(0)
      .and change { export_parts.count }.from(vulnerabilities_export_count).to(0)
      .and change { uploads.count }.from(vulnerabilities_export_count * 2).to(0)
  end

  it 'does not leave the export parts uploads behind', :sidekiq_inline do
    part_uploads = uploads.for_model_type_and_id(Vulnerabilities::Export::Part, parts.map(&:id))

    expect { execute }.to change { part_uploads.count }.from(vulnerabilities_export_count).to(0)
  end
end
