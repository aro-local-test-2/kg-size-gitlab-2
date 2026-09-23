# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry artifact page', :js, :with_current_organization,
  feature_category: :artifact_registry do
  let(:user) { create(:user, organizations: [current_organization]) }

  let(:slug) { 'acme' }
  let(:repositories_base_path) { "/o/#{current_organization.path}/-/artifact_registry/#{slug}/repositories" }
  let(:client) { instance_double(::ArtifactRegistry::Client) }

  let_it_be(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  let(:registry) do
    ::ArtifactRegistry::NamespaceMapping::Registry.new(
      slug: slug, status: 'active', created_at: '2026-07-01T10:00:00Z'
    )
  end

  let(:artifact_id) { '01937b2e-0000-7000-8000-000000000001' }

  let(:attributes) do
    {
      'id' => '01937b2e-0000-7000-8000-000000000010',
      'name' => name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'artifacts_count' => 3,
      'downloads_count' => 340,
      'size_bytes' => 2048,
      'created_at' => '2026-05-12T09:24:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z'
    }
  end

  let(:repository) { ::ArtifactRegistry::Repository.new(attributes) }

  let(:permissions) do
    ::ArtifactRegistry::Permissions::Verdicts.new(
      ::ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true),
      scope: :repository, read: :repository, slug: slug
    )
  end

  before do
    allow_next_found_instance_of(::ArtifactRegistry::NamespaceMapping) do |mapping|
      allow(mapping).to receive(:registry).and_return(registry)
    end

    allow(::ArtifactRegistry::Client).to receive(:new)
      .with(current_user: user, organization: current_organization).and_return(client)
    allow(client).to receive(:repository)
      .with(slug: slug, name: name, include_permissions: false).and_return(repository)
    allow(client).to receive(:repository)
      .with(slug: slug, name: name, include_permissions: true)
      .and_return(::ArtifactRegistry::Repository.new(attributes, permissions))

    sign_in(user)
  end

  describe 'a package the schema resolves' do
    let(:name) { 'maven-repository' }
    let(:format) { 'maven' }

    let(:package) do
      ::ArtifactRegistry::MavenPackage.new(
        'id' => artifact_id,
        'group_id' => 'com.example.payments',
        'artifact_id' => 'payment-core'
      )
    end

    let(:versions_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::Version.new(
            'id' => '01937b2e-0000-7000-8000-000000000101',
            'version' => '3.2.1',
            'created_at' => '2026-06-10T00:00:00Z'
          ),
          ::ArtifactRegistry::Version.new(
            'id' => '01937b2e-0000-7000-8000-000000000102',
            'version' => '2.0.0',
            'created_at' => '2026-04-02T00:00:00Z'
          )
        ]
      )
    end

    before do
      allow(client).to receive(:package)
        .with(slug: slug, repository_name: name, format: format, id: artifact_id)
        .and_return(package)
      allow(client).to receive(:versions)
        .with(hash_including(slug: slug, repository_name: name, format: format, package_id: artifact_id))
        .and_return(versions_page)

      visit "#{repositories_base_path}/#{name}/#{artifact_id}"
    end

    it 'heads the page with the coordinates the read returned' do
      within_testid('repositories-shell') do
        expect(find_by_testid('artifact-name')).to have_text('com.example.payments:payment-core')
        expect(find_by_testid('artifact-format-name', visible: :all)).to have_text(:all, 'Maven')
      end
    end

    it 'renders the versions the connection returned' do
      within_testid('repositories-shell') do
        expect(page).to have_selector('[data-testid="version-name"]', count: 2)
        expect(page).to have_css('[data-testid="version-name"]', text: '3.2.1')
        expect(page).to have_css('[data-testid="version-name"]', text: '2.0.0')
      end
    end

    it 'passes axe automated accessibility testing' do
      expect(find_by_testid('artifact-name')).to have_text('com.example.payments:payment-core')
      expect(page).to have_css('[data-testid="version-name"]', text: '3.2.1')
      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  describe 'a container image the schema resolves' do
    let(:name) { 'container-images' }
    let(:format) { 'docker' }

    let(:image) do
      ::ArtifactRegistry::Image.new('id' => artifact_id, 'name' => 'payment-service')
    end

    let(:manifests_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::Manifest.new(
            'id' => '01937b2e-0000-7000-8000-000000000201',
            'digest' => 'sha256:3f2a9c1e7b4d8a6f0c5e2b9d1a7f4c8e6b3d0a9f2c5e8b1d4a7f0c3e6b9d2a5f',
            'media_type' => 'application/vnd.oci.image.index.v1+json',
            'artifact_type' => nil,
            'subject_digest' => nil,
            'size' => 2097152,
            'created_at' => '2026-06-10T00:00:00Z'
          ),
          ::ArtifactRegistry::Manifest.new(
            'id' => '01937b2e-0000-7000-8000-000000000202',
            'digest' => 'sha256:9e1d4b7a2c5f8e0b3d6a9c2f5e8b1d4a7c0f3e6b9d2a5c8f1e4b7d0a3c6f9e2b',
            'media_type' => 'application/vnd.oci.image.manifest.v1+json',
            'artifact_type' => nil,
            'subject_digest' => nil,
            'size' => 1048576,
            'created_at' => '2026-04-02T00:00:00Z'
          )
        ]
      )
    end

    before do
      allow(client).to receive(:image)
        .with(slug: slug, repository_name: name, format: format, id: artifact_id)
        .and_return(image)
      allow(client).to receive(:manifests)
        .with(hash_including(slug: slug, repository_name: name, format: format, image_id: artifact_id))
        .and_return(manifests_page)

      visit "#{repositories_base_path}/#{name}/#{artifact_id}"
    end

    it 'heads the page with the image name the read returned' do
      within_testid('repositories-shell') do
        expect(find_by_testid('artifact-name')).to have_text('payment-service')
        expect(find_by_testid('artifact-format-name', visible: :all)).to have_text(:all, 'Docker')
      end
    end

    it 'renders the manifests the connection returned', :aggregate_failures do
      within_testid('repositories-shell') do
        expect(page).to have_selector('[data-testid="manifest-digest"]', count: 2)
        expect(page).to have_css('[data-testid="manifest-digest"]', text: '3f2a9c1e7b4d')
        expect(page).to have_css('[data-testid="manifest-digest"]', text: '9e1d4b7a2c5f')
      end
    end

    it 'passes axe automated accessibility testing' do
      expect(find_by_testid('artifact-name')).to have_text('payment-service')
      expect(page).to have_css('[data-testid="manifest-digest"]', text: '3f2a9c1e7b4d')
      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  describe 'an artifact Artifact Registry does not hold' do
    let(:name) { 'maven-releases' }
    let(:format) { 'maven' }

    before do
      allow(client).to receive(:package)
        .with(slug: slug, repository_name: name, format: format, id: artifact_id)
        .and_return(nil)

      visit "#{repositories_base_path}/#{name}/#{artifact_id}"
    end

    it 'renders the in-SPA not-found state' do
      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Page not found')
      end
    end
  end
end
