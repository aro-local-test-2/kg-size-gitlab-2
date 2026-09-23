# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ArtifactRegistryRepositoryDetails'], feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject { described_class }

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRepositoryDetails') }

  it { is_expected.to require_graphql_authorizations(:read_artifact_registry) }

  it 'exposes every parent field plus the single-artifact fields and the artifact connections' do
    is_expected.to have_graphql_fields(
      :id, :name, :format, :kind, :visibility, :artifacts_count, :downloads_count, :size_bytes,
      :created_at, :created_by, :updated_by, :last_updated_at, :description, :settings, :user_permissions,
      :package, :image, :version, :manifest, :packages, :images, :upstream_repositories
    )
  end

  # Being unrelated types is what makes the fan-out unreachable rather than merely discouraged,
  # so it is asserted rather than left to a reader of the class definition.
  it 'is a distinct schema type from the list type, sharing no interface with it' do
    expect(described_class).not_to eq(GitlabSchema.types['ArtifactRegistryRepository'])
    expect(described_class.interfaces).to be_empty
    expect(GitlabSchema.types['ArtifactRegistryRepository'].fields).not_to have_key('packages')
    expect(GitlabSchema.types['ArtifactRegistryRepository'].fields).not_to have_key('images')
  end

  describe 'the artifact connections' do
    where(:field_name, :type_name, :resolver) do
      'packages' | 'ArtifactRegistryPackageConnection' | ::Resolvers::ArtifactRegistry::PackagesResolver
      'images'   | 'ArtifactRegistryImageConnection'   | ::Resolvers::ArtifactRegistry::ImagesResolver
    end

    with_them do
      let(:field) { described_class.fields[field_name] }

      it 'is the declared connection type, nullable, keyset-only, capped at 20, and budgeted',
        :aggregate_failures do
        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type).to be_nullable
        expect(field.arguments.keys).to contain_exactly('first', 'last', 'before', 'after')
        # `ArtifactRegistry::PaginatesLists` reads `max_page_size` off the field to cap `limit`.
        expect(field.max_page_size).to eq(20)
        expect(field.resolver).to eq(resolver)
        expect(field.description).to include('once per operation')
      end
    end
  end

  describe 'the single-artifact fields' do
    where(:field_name, :type_name, :resolver) do
      'package' | 'ArtifactRegistryPackageDetails' | ::Resolvers::ArtifactRegistry::PackageResolver
      'image'   | 'ArtifactRegistryImage'          | ::Resolvers::ArtifactRegistry::ImageResolver
    end

    with_them do
      let(:field) { described_class.fields[field_name] }

      it 'is the declared type, nullable, takes the AR ID alone, and is budgeted', :aggregate_failures do
        expect(field.type.unwrap.graphql_name).to eq(type_name)
        expect(field.type).to be_nullable
        expect(field.arguments.keys).to contain_exactly('id')
        expect(field.resolver).to eq(resolver)
        expect(field.description).to include('once per operation')
      end
    end
  end

  describe 'the version field' do
    # Sits outside the single-artifact table above: it takes the package ID alongside the version
    # ID, so its argument set is not the lone `id` that table pins.
    let(:field) { described_class.fields['version'] }

    it 'is the version detail type, nullable, takes both IDs, and is budgeted', :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryVersionDetails')
      expect(field.type).to be_nullable
      expect(field.arguments.keys).to contain_exactly('id', 'artifactId')
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::VersionResolver)
      expect(field.description).to include('once per operation')
    end
  end

  describe 'the manifest field' do
    # Sits outside the single-artifact table above: like `version` it takes two arguments -- the
    # image ID alongside the digest -- so its argument set is not the lone `id` that table pins.
    let(:field) { described_class.fields['manifest'] }

    it 'is the manifest detail type, nullable, takes both the image ID and the digest, and is budgeted',
      :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryManifestDetails')
      expect(field.type).to be_nullable
      expect(field.arguments.keys).to contain_exactly('artifactId', 'digest')
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::ManifestResolver)
      expect(field.description).to include('once per operation')
    end

    # Both arguments are required, and GraphQL implements experiment through the deprecation
    # mechanism, which cannot apply to a required argument, so neither carries an experiment marker
    # (matching the sibling single-artifact resolvers).
    it 'leaves the required arguments unmarked, since a required argument cannot be experiment',
      :aggregate_failures do
      expect(field.arguments.values)
        .to all(have_attributes(deprecation_reason: nil))
    end
  end

  describe 'the upstream list field' do
    let(:field) { described_class.fields['upstreamRepositories'] }

    it 'is the association list type, nullable, and budgeted', :aggregate_failures do
      expect(field.type.unwrap.graphql_name).to eq('ArtifactRegistryUpstreamRepositoryAssociation')
      expect(field.type).to be_nullable
      expect(field.type.list?).to be(true)
      expect(field.resolver).to eq(::Resolvers::ArtifactRegistry::UpstreamRepositoriesResolver)
      expect(field.description).to include('once per operation')
    end
  end

  it 'marks every field experiment ahead of general availability' do
    expect(described_class.fields.values)
      .to all(have_attributes(deprecation_reason: a_string_including('Status: Experiment.')))
  end
end
