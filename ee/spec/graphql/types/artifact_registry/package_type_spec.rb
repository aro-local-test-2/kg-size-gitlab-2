# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::ArtifactRegistry::PackageType, feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryPackage') }

  it 'unions the two package formats the Artifact Registry contract splits on' do
    expect(described_class.possible_types).to contain_exactly(
      ::Types::ArtifactRegistry::MavenPackageType,
      ::Types::ArtifactRegistry::NpmPackageType
    )
  end

  describe '.resolve_type' do
    it 'resolves a Maven package to the Maven type' do
      package = ::ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(package, {})).to be(::Types::ArtifactRegistry::MavenPackageType)
    end

    it 'resolves an npm package to the npm type' do
      package = ::ArtifactRegistry::NpmPackage.new('id' => 'c3d4e5f6-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(package, {})).to be(::Types::ArtifactRegistry::NpmPackageType)
    end

    it 'rejects a value object no member type covers' do
      expect { described_class.resolve_type(::ArtifactRegistry::Image.new, {}) }
        .to raise_error(described_class::TypeNotSupportedError)
    end

    context 'when the element arrives wrapped in an ArtifactPresenter' do
      let(:repository) { instance_double(::ArtifactRegistry::Repository) }
      let(:organization) { build_stubbed(:organization) }

      def wrapped(value_object)
        ::ArtifactRegistry::ArtifactPresenter.new(value_object, repository: repository, organization: organization)
      end

      it 'unwraps the delegate and resolves a wrapped Maven element to the Maven type' do
        package = ::ArtifactRegistry::MavenPackage.new('id' => 'a1b2c3d4-0000-0000-0000-000000000000')

        expect(described_class.resolve_type(wrapped(package), {})).to be(::Types::ArtifactRegistry::MavenPackageType)
      end

      it 'unwraps the delegate and resolves a wrapped npm element to the npm type' do
        package = ::ArtifactRegistry::NpmPackage.new('id' => 'c3d4e5f6-0000-0000-0000-000000000000')

        expect(described_class.resolve_type(wrapped(package), {})).to be(::Types::ArtifactRegistry::NpmPackageType)
      end
    end
  end
end
