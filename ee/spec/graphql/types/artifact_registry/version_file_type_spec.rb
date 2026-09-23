# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::ArtifactRegistry::VersionFileType, feature_category: :artifact_registry do
  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryVersionFile') }

  it 'unions the two file formats the Artifact Registry contract splits on' do
    expect(described_class.possible_types).to contain_exactly(
      ::Types::ArtifactRegistry::MavenVersionFileType,
      ::Types::ArtifactRegistry::NpmVersionFileType
    )
  end

  describe '.resolve_type' do
    it 'resolves a Maven file to the Maven file type' do
      file = ::ArtifactRegistry::MavenFile.new('id' => 'f1000000-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(file, {})).to be(::Types::ArtifactRegistry::MavenVersionFileType)
    end

    it 'resolves an npm file to the npm file type' do
      file = ::ArtifactRegistry::NpmFile.new('id' => 'f2000000-0000-0000-0000-000000000000')

      expect(described_class.resolve_type(file, {})).to be(::Types::ArtifactRegistry::NpmVersionFileType)
    end

    it 'rejects a value object no member type covers' do
      expect { described_class.resolve_type(::ArtifactRegistry::Image.new, {}) }
        .to raise_error(described_class::TypeNotSupportedError)
    end
  end
end
