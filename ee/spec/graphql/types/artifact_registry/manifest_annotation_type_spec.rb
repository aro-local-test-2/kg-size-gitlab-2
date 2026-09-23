# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryManifestAnnotation'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryManifestAnnotation') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the annotation key and value' do
    is_expected.to have_graphql_fields(:key, :value)
  end

  describe 'field types and hash-key wiring' do
    where(:field_name, :hash_key) do
      'key'   | 'key'
      'value' | 'value'
    end

    with_them do
      let(:field) { described_class.fields[field_name] }

      # Each pair reaches the schema as a bare Hash the details type builds, so a field reads its
      # own string key; a mismatch would silently null the field rather than fail this spec.
      it 'renders a non-null String read from the value-object hash key', :aggregate_failures do
        expect(field.type.unwrap.graphql_name).to eq('String')
        expect(field.type.non_null?).to be(true)
        expect(field.hash_key).to eq(hash_key)
      end
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
