# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistry'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistry') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes exactly the namespace UUID, slug, status, creation time, and the user permissions block' do
    is_expected.to have_graphql_fields(:id, :slug, :status, :created_at, :user_permissions)
  end

  describe 'field types' do
    # slug and createdAt are nullable so the unknown 404 state renders without an
    # InvalidNullError; status and id are non-null because every resolved path sets them.
    where(:field_name, :type_name, :nullable) do
      'id'              | 'ID'                                    | false
      'slug'            | 'String'                                | true
      'status'          | 'String'                                | false
      'createdAt'       | 'Time'                                  | true
      'userPermissions' | 'ArtifactRegistryNamespacePermissions' | false
    end

    with_them do
      it 'renders the field with the declared type and nullability', :aggregate_failures do
        field = described_class.fields[field_name]

        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type.non_null?).to eq(!nullable)
      end
    end
  end

  it 'resolves the user permissions block through the namespace details read, marked experiment',
    :aggregate_failures do
    field = described_class.fields['userPermissions']

    expect(field.resolver).to eq(Resolvers::ArtifactRegistry::NamespacePermissionsResolver)
    expect(field.deprecation_reason).to include('Status: Experiment.')
    expect(field.description).to include('artifact_registry_ui')
  end

  it 'keeps status a String rather than an enum so unrecognized values reach the response' do
    expect(described_class.fields['status'].type.unwrap).to eq(GraphQL::Types::String)
  end
end
