# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryVersion'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryVersion') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the version fields plus the resolved publish attribution' do
    is_expected.to have_graphql_fields(
      :id, :version, :dist_tags, :size_bytes, :created_at, :created_by, :project, :commit_sha, :commit_path
    )
  end

  describe 'field types' do
    it 'renders the identifier as a non-null ID' do
      field = described_class.fields['id']

      expect(field.type.unwrap.graphql_name).to eq('ID')
      expect(field.type).to be_non_null
    end

    it 'renders the version as a non-null String' do
      field = described_class.fields['version']

      expect(field.type.unwrap.graphql_name).to eq('String')
      expect(field.type).to be_non_null
    end

    it 'renders the dist-tags as a non-null list of non-null Strings' do
      field = described_class.fields['distTags']

      expect(field.type.to_type_signature).to eq('[String!]!')
    end

    it 'renders the timestamp as a nullable Time, because Artifact Registry may store none' do
      field = described_class.fields['createdAt']

      expect(field.type.unwrap.graphql_name).to eq('Time')
      expect(field.type).to be_nullable
    end

    it 'renders the size as a nullable BigInt, because Maven withholds it until serialized' do
      field = described_class.fields['sizeBytes']

      expect(field.type.unwrap.graphql_name).to eq('BigInt')
      expect(field.type).to be_nullable
    end

    it 'resolves the creator through the existing user type, nullable for an unresolvable reference' do
      field = described_class.fields['createdBy']

      expect(field.type.unwrap.graphql_name).to eq('UserCore')
      expect(field.type).to be_nullable
    end

    it 'resolves the project through the existing project type, nullable for an unresolvable reference' do
      field = described_class.fields['project']

      expect(field.type.unwrap.graphql_name).to eq('Project')
      expect(field.type).to be_nullable
    end

    it 'renders the commit SHA and path as nullable Strings' do
      expect(described_class.fields['commitSha'].type.unwrap.graphql_name).to eq('String')
      expect(described_class.fields['commitSha'].type).to be_nullable
      expect(described_class.fields['commitPath'].type.unwrap.graphql_name).to eq('String')
      expect(described_class.fields['commitPath'].type).to be_nullable
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
