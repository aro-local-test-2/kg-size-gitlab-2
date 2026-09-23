# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ArtifactPresenter, feature_category: :artifact_registry do
  let(:organization) { build_stubbed(:organization) }

  # A RepositoryPresenter, matching what PackagesResolver passes in production, so
  # repository.organization resolves the way a child resolver reads it.
  let(:repository) do
    ArtifactRegistry::RepositoryPresenter.new(
      ArtifactRegistry::Repository.new('name' => 'maven-releases', 'format' => 'maven'),
      organization: organization
    )
  end

  subject(:presenter) do
    described_class.new(value_object, repository: repository, organization: organization)
  end

  describe 'the repository and organization readers' do
    let(:value_object) { ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000') }

    it 'exposes the repository and organization it was read through', :aggregate_failures do
      expect(presenter.repository).to be(repository)
      expect(presenter.organization).to be(organization)
    end
  end

  describe 'delegation to a wrapped package' do
    let(:value_object) do
      ArtifactRegistry::MavenPackage.new(
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'group_id' => 'com.example.tools',
        'artifact_id' => 'payment-core'
      )
    end

    it 'delegates the value object readers unchanged', :aggregate_failures do
      expect(presenter.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(presenter.group_id).to eq('com.example.tools')
      expect(presenter.artifact_id).to eq('payment-core')
    end

    it 'unwraps to the wrapped value object through the delegate' do
      expect(presenter.__getobj__).to be(value_object)
    end

    it 'compares equal to the wrapped value object, so an ordered assertion still sees it' do
      expect(presenter).to eq(value_object)
    end
  end

  describe 'delegation to a wrapped image' do
    let(:value_object) do
      ArtifactRegistry::Image.new('id' => 'b2c3d4e5-0000-0000-0000-000000000000', 'name' => 'api-gateway')
    end

    it 'covers the image family through the same presenter', :aggregate_failures do
      expect(presenter.id).to eq('b2c3d4e5-0000-0000-0000-000000000000')
      expect(presenter.name).to eq('api-gateway')
      expect(presenter.repository).to be(repository)
      expect(presenter.organization).to be(organization)
    end
  end

  describe 'the required attributes' do
    let(:value_object) { ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000') }

    it 'requires the repository, so a child connection cannot resolve without its context' do
      expect { described_class.new(value_object, organization: organization) }
        .to raise_error(ArgumentError, /repository/)
    end

    it 'requires the organization, so a child connection cannot resolve without its context' do
      expect { described_class.new(value_object, repository: repository) }
        .to raise_error(ArgumentError, /organization/)
    end
  end

  describe '#declarative_policy_subject' do
    let(:value_object) { ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000') }

    it 'points authorization at the organization rather than the bare value object' do
      expect(presenter.declarative_policy_subject).to be(organization)
    end

    it 'resolves to a policy, where the bare value object has none', :aggregate_failures do
      expect { DeclarativePolicy.class_for(value_object) }.to raise_error(RuntimeError)
      expect { DeclarativePolicy.class_for(presenter.declarative_policy_subject) }.not_to raise_error
    end
  end
end
