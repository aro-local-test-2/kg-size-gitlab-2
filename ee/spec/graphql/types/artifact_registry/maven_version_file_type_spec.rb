# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryMavenVersionFile'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryMavenVersionFile') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes the identifier plus the Maven file fields' do
    is_expected.to have_graphql_fields(:id, :file_name, :size_bytes, :sha256, :sha1, :sha512, :md5, :created_at)
  end

  describe 'field nullability' do
    it 'renders the required checksums non-null and the deploy-dependent ones nullable',
      :aggregate_failures do
      expect(described_class.fields['sha256'].type).to be_non_null
      expect(described_class.fields['sha1'].type).to be_non_null
      expect(described_class.fields['sha512'].type).to be_non_null
      # md5 is nullable because a deploy may store none; createdAt until AR serializes the column.
      expect(described_class.fields['md5'].type).to be_nullable
      expect(described_class.fields['createdAt'].type).to be_nullable
    end

    it 'renders the size as a non-null BigInt' do
      field = described_class.fields['sizeBytes']

      expect(field.type.unwrap.graphql_name).to eq('BigInt')
      expect(field.type).to be_non_null
    end
  end
end
