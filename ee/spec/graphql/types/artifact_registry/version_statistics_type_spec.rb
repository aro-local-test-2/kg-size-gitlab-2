# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryVersionStatistics'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryVersionStatistics') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes filesCount alone, omitting the endpoint fields Phase 1 does not render' do
    is_expected.to have_graphql_fields(:files_count)
  end

  it 'renders filesCount as a nullable BigInt' do
    field = described_class.fields['filesCount']

    expect(field.type.unwrap.graphql_name).to eq('BigInt')
    expect(field.type).to be_nullable
  end
end
