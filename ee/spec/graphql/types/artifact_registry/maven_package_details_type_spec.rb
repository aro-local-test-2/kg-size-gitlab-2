# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryMavenPackageDetails'], feature_category: :artifact_registry do
  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryMavenPackageDetails') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes every Maven list-element field, including the versions connection' do
    is_expected.to have_graphql_fields(
      :id, :group_id, :artifact_id, :last_downloaded_at, :versions
    )
  end

  # Being an unrelated type from the list element is what makes a child connection unnameable
  # under the packages connection, so it is asserted rather than left to a reader.
  it 'is a distinct schema type from the Maven list element, sharing no interface with it',
    :aggregate_failures do
    expect(described_class).not_to eq(GitlabSchema.types['ArtifactRegistryMavenPackage'])
    expect(described_class.interfaces).to be_empty
  end
end
