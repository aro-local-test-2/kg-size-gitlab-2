# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::RepositoryResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  # The flag-off and denial behaviors are covered end to end by
  # ee/spec/requests/api/graphql/organizations/artifact_registry_repository_spec.rb.
  # The detail type, not the list type: this is the only field from which an artifact
  # connection is selectable.
  it 'resolves the repository detail type, nullable' do
    expect(described_class.type).to eq(::Types::ArtifactRegistry::RepositoryDetailsType)
    expect(described_class.type.non_null?).to be(false)
  end

  it 'requires a name argument' do
    argument = described_class.arguments['name']

    expect(argument.type.to_type_signature).to eq('String!')
  end

  describe 'the resolved repository' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:current_user) { create(:organization_user, organization: organization).user }

    let(:repository) { ArtifactRegistry::Repository.new('name' => 'maven-releases', 'format' => 'maven') }
    let(:client) { instance_double(ArtifactRegistry::Client, repository: repository) }
    let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: 'resolved-handle', status: 'active') }
    let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }

    before do
      allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
      allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
    end

    subject(:resolve_repository) do
      resolve(described_class, obj: organization, args: { name: 'maven-releases' },
        ctx: { current_user: current_user })
    end

    it 'presents the repository with the organization its child connections read through',
      :aggregate_failures do
      presented = resolve_repository

      expect(presented).to be_a(ArtifactRegistry::RepositoryPresenter)
      expect(presented.organization).to be(organization)
      expect(presented.name).to eq('maven-releases')
    end

    context 'when the client reports the repository missing' do
      let(:repository) { nil }

      it 'resolves null rather than presenting an absent repository' do
        expect(resolve_repository).to be_nil
      end
    end
  end
end
