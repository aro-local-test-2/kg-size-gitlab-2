# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryManifestDetails'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryManifestDetails') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the identifier and the detail fields the manifest page reads' do
    is_expected.to have_graphql_fields(
      :id, :digest, :media_type, :artifact_type, :subject_digest, :size, :created_at,
      :architecture, :os, :os_variant, :tags, :tags_count, :children, :children_count,
      :parent_digests, :parents_count, :referrers_count, :annotations, :referrers
    )
  end

  it 'keeps the preview arrays list-only, both in the schema and at lookup', :aggregate_failures do
    %w[tagsPreview childrenPreview parentsPreview].each do |name|
      expect(described_class.fields).not_to have_key(name)
      expect(described_class.get_field(name)).to be_nil
    end
  end

  describe 'the referrers connection field' do
    let(:field) { described_class.fields['referrers'] }

    it 'is the unwidened manifest element connection, nullable, keyset-only, capped at 20',
      :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryManifestConnection')
      expect(field.type).to be_nullable
      expect(field.arguments.keys).to contain_exactly('first', 'last', 'before', 'after')
      expect(field.max_page_size).to eq(::ArtifactRegistry::PaginatesLists::MAX_PAGE_SIZE)
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::ManifestReferrersResolver)
      expect(field.description).to include('once per operation')
    end
  end

  describe 'field types and nullability' do
    where(:field_name, :type_name, :null) do
      'id'             | 'ID'     | false
      'digest'         | 'String' | false
      'mediaType'      | 'String' | false
      'artifactType'   | 'String' | true
      'subjectDigest'  | 'String' | true
      'size'           | 'BigInt' | false
      'createdAt'      | 'Time'   | true
      'architecture'   | 'String' | true
      'os'             | 'String' | true
      'osVariant'      | 'String' | true
      'tagsCount'      | 'Int'    | true
      'childrenCount'  | 'Int'    | true
      'parentsCount'   | 'Int'    | true
      'referrersCount' | 'Int'    | true
    end

    with_them do
      it 'renders the field as the declared type and nullability' do
        field = described_class.fields[field_name]

        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type.non_null?).to eq(!null)
      end
    end

    it 'renders tags as a nullable list of non-null strings' do
      field = described_class.fields['tags']

      expect(field.type.unwrap.graphql_name).to eq('String')
      expect(field.type.non_null?).to be(false)
      expect(field.type.of_type.non_null?).to be(true)
    end

    it 'renders parentDigests as a nullable list of non-null strings' do
      field = described_class.fields['parentDigests']

      expect(field.type.unwrap.graphql_name).to eq('String')
      expect(field.type.non_null?).to be(false)
      expect(field.type.of_type.non_null?).to be(true)
    end

    it 'renders children as a nullable list of the non-null platform type' do
      field = described_class.fields['children']

      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryManifestPlatform')
      expect(field.type.non_null?).to be(false)
      expect(field.type.of_type.non_null?).to be(true)
    end

    it 'renders annotations as a nullable list of the non-null annotation type' do
      field = described_class.fields['annotations']

      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryManifestAnnotation')
      expect(field.type.non_null?).to be(false)
      expect(field.type.of_type.non_null?).to be(true)
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
