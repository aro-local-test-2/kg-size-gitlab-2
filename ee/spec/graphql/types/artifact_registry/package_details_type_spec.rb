# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::ArtifactRegistry::PackageDetailsType, feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryPackageDetails') }

  it 'unions the two package detail formats' do
    expect(described_class.possible_types).to contain_exactly(
      ::Types::ArtifactRegistry::MavenPackageDetailsType,
      ::Types::ArtifactRegistry::NpmPackageDetailsType
    )
  end

  describe '.resolve_type' do
    let(:repository) { instance_double(::ArtifactRegistry::Repository) }
    let(:organization) { build_stubbed(:organization) }

    def wrapped(value_object)
      ::ArtifactRegistry::ArtifactPresenter.new(value_object, repository: repository, organization: organization)
    end

    it 'resolves a Maven package to the Maven detail type' do
      package = ::ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(package, {})).to be(::Types::ArtifactRegistry::MavenPackageDetailsType)
    end

    it 'resolves an npm package to the npm detail type' do
      package = ::ArtifactRegistry::NpmPackage.new('id' => 'c3d4e5f6-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(package, {})).to be(::Types::ArtifactRegistry::NpmPackageDetailsType)
    end

    it 'unwraps a presenter and resolves a wrapped Maven element to the Maven detail type' do
      package = ::ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(wrapped(package), {}))
        .to be(::Types::ArtifactRegistry::MavenPackageDetailsType)
    end

    it 'unwraps a presenter and resolves a wrapped npm element to the npm detail type' do
      package = ::ArtifactRegistry::NpmPackage.new('id' => 'c3d4e5f6-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(wrapped(package), {}))
        .to be(::Types::ArtifactRegistry::NpmPackageDetailsType)
    end

    it 'rejects a value object no member type covers' do
      expect { described_class.resolve_type(::ArtifactRegistry::Image.new, {}) }
        .to raise_error(described_class::TypeNotSupportedError)
    end
  end
end
