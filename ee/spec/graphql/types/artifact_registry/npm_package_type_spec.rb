# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryNpmPackage'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryNpmPackage') }

  it 'exposes the identifier, the name, the version count, the pull timestamp, and the ' \
    'versions connection' do
    is_expected.to have_graphql_fields(
      :id, :name, :scope, :versions_count, :last_downloaded_at, :versions
    )
  end

  describe 'field types' do
    where(:field_name, :type_name, :non_null) do
      'id'               | 'ID'     | true
      'name'             | 'String' | true
      'scope'            | 'String' | false
      'versionsCount'    | 'Int'    | false
      'lastDownloadedAt' | 'Time'   | false
    end

    with_them do
      it 'renders the field as the declared type and nullability' do
        field = described_class.fields[field_name]

        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type.non_null?).to be(non_null)
      end
    end
  end

  describe 'the versions connection' do
    let(:field) { described_class.fields['versions'] }

    it 'returns the version connection, nullable so a failed read hides it', :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryVersionConnection')
      expect(field.type).to be_nullable
    end

    it 'is resolved by the versions resolver' do
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::VersionsResolver)
    end

    # `ArtifactRegistry::PaginatesLists` reads this off the field to cap the outbound `limit`.
    it 'caps a page at 20 rows rather than the schema default' do
      expect(field.max_page_size).to eq(20)
    end

    it 'tells the caller the connection is budgeted per package in a page' do
      expect(field.description).to include('once per package in a page')
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
