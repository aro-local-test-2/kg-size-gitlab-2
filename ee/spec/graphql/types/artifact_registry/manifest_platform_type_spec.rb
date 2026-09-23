# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryManifestPlatform'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryManifestPlatform') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the child digest and its platform triple' do
    is_expected.to have_graphql_fields(:digest, :architecture, :os, :os_variant)
  end

  describe 'field types, nullability, and hash-key wiring' do
    where(:field_name, :null, :hash_key) do
      'digest'       | false | 'digest'
      'architecture' | true  | 'architecture'
      'os'           | true  | 'os'
      'osVariant'    | true  | 'os_variant'
    end

    with_them do
      let(:field) { described_class.fields[field_name] }

      # A child reaches the schema as a bare Hash, so each field reads its own string key; a
      # mismatch would silently null the field rather than fail this spec.
      it 'renders a String with the declared nullability, read from the value-object hash key',
        :aggregate_failures do
        expect(field.type.unwrap.graphql_name).to eq('String')
        expect(field.type.non_null?).to eq(!null)
        expect(field.hash_key).to eq(hash_key)
      end
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
