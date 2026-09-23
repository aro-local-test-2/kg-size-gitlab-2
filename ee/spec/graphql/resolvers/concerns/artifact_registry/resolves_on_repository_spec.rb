# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ResolvesOnRepository, feature_category: :artifact_registry do
  let(:organization) { instance_double(Organizations::Organization) }
  let(:repository) { ArtifactRegistry::Repository.new('name' => 'maven-releases', 'format' => 'maven') }
  let(:presented_repository) { ArtifactRegistry::RepositoryPresenter.new(repository, organization: organization) }
  let(:element) { ArtifactRegistry::MavenPackage.new('id' => 'a1') }

  let(:adapter_class) do
    Class.new do
      include ::ArtifactRegistry::ResolvesOnRepository

      def initialize(object)
        @object = object
      end

      def repository
        presented_repository
      end

      def org
        artifact_registry_organization
      end

      def wrap(element)
        wrap_in_artifact_presenter(element)
      end
    end
  end

  subject(:adapter) { adapter_class.new(presented_repository) }

  it 'reads the repository off @object, so the presenter context stays reachable' do
    expect(adapter.repository).to eq(presented_repository)
  end

  it 'reads the organization through the presenter, not the base resolver object' do
    expect(adapter.org).to eq(organization)
  end

  it 'wraps an element in an ArtifactPresenter carrying the repository and organization',
    :aggregate_failures do
    result = adapter.wrap(element)

    expect(result).to be_a(::ArtifactRegistry::ArtifactPresenter)
    expect(result.id).to eq('a1')
    expect(result.repository).to eq(presented_repository)
    expect(result.organization).to eq(organization)
  end
end
