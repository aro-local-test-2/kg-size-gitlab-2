# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryUpstreamRepositoryAssociation'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryUpstreamRepositoryAssociation') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the identifier, the position, and the upstream repository summary' do
    is_expected.to have_graphql_fields(:id, :position, :upstream_repository)
  end

  describe 'field types' do
    where(:field_name, :type_name, :non_null) do
      'id'                 | 'ID'                                        | true
      'position'           | 'Int'                                       | true
      'upstreamRepository' | 'ArtifactRegistryUpstreamRepositorySummary' | true
    end

    with_them do
      it 'renders the field as the declared type and nullability', :aggregate_failures do
        field = described_class.fields[field_name]

        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type.non_null?).to be(non_null)
      end
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
