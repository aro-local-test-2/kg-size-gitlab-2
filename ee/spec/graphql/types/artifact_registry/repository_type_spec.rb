# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryRepository'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRepository') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  # No artifact connection here. It lives on ArtifactRegistryRepositoryDetails, so a listed
  # repository cannot fan out one Artifact Registry request per row.
  it 'exposes the list fields and the read fields the edit prefill needs' do
    is_expected.to have_graphql_fields(
      :id, :name, :format, :kind, :visibility, :artifacts_count, :downloads_count, :size_bytes,
      :created_at, :created_by, :updated_by, :last_updated_at, :description, :settings, :user_permissions
    )
  end

  describe 'field types' do
    where(:field_name, :type_name) do
      'id'             | 'ID'
      'name'           | 'String'
      'format'         | 'ArtifactRegistryRepositoryFormat'
      'kind'           | 'ArtifactRegistryRepositoryKind'
      'visibility'     | 'ArtifactRegistryRepositoryVisibility'
      'artifactsCount' | 'BigInt'
      'downloadsCount' | 'BigInt'
      'sizeBytes'      | 'BigInt'
      'createdAt'      | 'Time'
      'createdBy'      | 'UserCore'
      'updatedBy'      | 'UserCore'
      'lastUpdatedAt'  | 'Time'
      'description'    | 'String'
      'settings'       | 'ArtifactRegistryRemoteSettings'
      'userPermissions' | 'ArtifactRegistryRepositoryPermissions'
    end

    with_them do
      it 'renders the field as the declared type' do
        expect(described_class.fields[field_name].type.unwrap.graphql_name).to eq(type_name)
      end
    end
  end

  it 'declares id non-null, because Artifact Registry returns an identifier for every repository' do
    expect(described_class.fields['id'].type).to be_non_null
  end

  it 'leaves lastUpdatedAt nullable, because a repository whose content never changed reports none' do
    expect(described_class.fields['lastUpdatedAt'].type).to be_nullable
  end

  it 'leaves settings nullable, because only a remote repository defines them' do
    expect(described_class.fields['settings'].type).to be_nullable
  end

  it 'declares userPermissions non-null and names the flag whose off state nulls the parent', :aggregate_failures do
    field = described_class.fields['userPermissions']

    expect(field.type).to be_non_null
    expect(field.description).to include('artifact_registry_ui')
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end

  describe 'the connection type' do
    subject(:connection_type) { described_class.connection_type }

    it 'keeps the derived name while carrying the namespace permissions block', :aggregate_failures do
      expect(connection_type.graphql_name).to eq('ArtifactRegistryRepositoryConnection')
      expect(connection_type).to be < Types::ArtifactRegistry::RepositoryConnectionType
      expect(connection_type.fields.keys).to contain_exactly('edges', 'nodes', 'pageInfo', 'userPermissions')
    end

    it 'declares userPermissions non-null, typed as the namespace block, and experiment', :aggregate_failures do
      field = connection_type.fields['userPermissions']

      expect(field.type).to be_non_null
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryNamespacePermissions')
      expect(field.deprecation_reason).to include('Status: Experiment.')
      expect(field.description).to include('artifact_registry_ui')
    end
  end

  describe 'the format enum' do
    let(:enum) { described_class.fields['format'].type.unwrap }

    where(:artifact_registry_value, :graphql_value) do
      'docker' | 'DOCKER'
      'oci'    | 'OCI'
      'maven'  | 'MAVEN'
      'npm'    | 'NPM'
    end

    with_them do
      it 'decodes the Artifact Registry format' do
        expect(enum.coerce_isolated_result(artifact_registry_value)).to eq(graphql_value)
      end
    end

    it 'declares no value outside the Artifact Registry contract' do
      expect(enum.values.keys).to contain_exactly('DOCKER', 'OCI', 'MAVEN', 'NPM')
    end
  end

  describe 'the kind enum' do
    let(:enum) { described_class.fields['kind'].type.unwrap }

    where(:artifact_registry_value, :graphql_value) do
      'hosted'  | 'HOSTED'
      'virtual' | 'VIRTUAL'
      'remote'  | 'REMOTE'
    end

    with_them do
      it 'decodes the Artifact Registry kind' do
        expect(enum.coerce_isolated_result(artifact_registry_value)).to eq(graphql_value)
      end
    end

    it 'declares no value outside the Artifact Registry contract' do
      expect(enum.values.keys).to contain_exactly('HOSTED', 'VIRTUAL', 'REMOTE')
    end
  end

  describe 'the visibility enum' do
    let(:enum) { described_class.fields['visibility'].type.unwrap }

    where(:artifact_registry_value, :graphql_value) do
      'private'  | 'PRIVATE'
      'internal' | 'INTERNAL'
      'public'   | 'PUBLIC'
    end

    with_them do
      it 'decodes the Artifact Registry visibility' do
        expect(enum.coerce_isolated_result(artifact_registry_value)).to eq(graphql_value)
      end
    end

    it 'declares no value outside the Artifact Registry contract' do
      expect(enum.values.keys).to contain_exactly('PRIVATE', 'INTERNAL', 'PUBLIC')
    end
  end
end
