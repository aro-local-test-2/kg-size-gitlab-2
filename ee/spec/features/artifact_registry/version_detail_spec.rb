# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry version page', :js, :with_current_organization,
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
  let(:version_id) { '01937b2e-0000-7000-8000-000000000101' }
  let(:version_page_path) { "#{repositories_base_path}/#{name}/#{artifact_id}/versions/#{version_id}" }

  let(:files) { [] }
  let(:files_page) { ::ArtifactRegistry::Page.new(nodes: files) }
  let(:file_names) { files.map(&:file_name) }

  let(:repository) do
    ::ArtifactRegistry::Repository.new(
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
    )
  end

  let(:version) do
    ::ArtifactRegistry::Version.new(
      'id' => version_id,
      'version' => version_string,
      'created_at' => '2026-06-10T00:00:00Z',
      'size' => 4096,
      'package_id' => artifact_id
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
    allow(client).to receive(:package)
      .with(slug: slug, repository_name: name, format: format, id: artifact_id)
      .and_return(package)
    allow(client).to receive(:version)
      .with(slug: slug, repository_name: name, format: format, version_id: version_id)
      .and_return(version)
    allow(client).to receive(:version_files)
      .with(hash_including(slug: slug, repository_name: name, format: format, version_id: version_id))
      .and_return(files_page)
    allow(client).to receive(:version_statistics)
      .with(slug: slug, repository_name: name, format: format, version_id: version_id)
      .and_return(::ArtifactRegistry::VersionStatistics.new('files_count' => files.size))

    sign_in(user)
  end

  shared_examples 'a version the schema resolves' do
    context 'when landing on the Overview tab' do
      before do
        visit version_page_path
      end

      it 'heads the page with the version and artifact the read returned', :aggregate_failures do
        within_testid('repositories-shell') do
          expect(find_by_testid('version-name')).to have_text(version_string)
          expect(find_by_testid('version-format-name', visible: :all)).to have_text(:all, format_label)
          expect(find_by_testid('artifact-name')).to have_text(artifact_name)
        end

        expect(client).to have_received(:version)
          .with(slug: slug, repository_name: name, format: format, version_id: version_id).once
        expect(client).to have_received(:version_statistics)
          .with(slug: slug, repository_name: name, format: format, version_id: version_id).once
        expect(client).not_to have_received(:version_files)
      end

      it 'lists the files the sub-collection read returned when the files tab is activated',
        :aggregate_failures do
        within_testid('repositories-shell') do
          expect(find_by_testid('version-name')).to have_text(version_string)

          click_link files_tab_title

          file_names.each do |file_name|
            expect(page).to have_css('[data-testid="file-name"]', text: file_name)
          end
        end

        expect(client).to have_received(:version)
          .with(slug: slug, repository_name: name, format: format, version_id: version_id).twice
        expect(client).to have_received(:version_statistics)
          .with(slug: slug, repository_name: name, format: format, version_id: version_id).once
        expect(client).to have_received(:version_files)
          .with(hash_including(slug: slug, repository_name: name, format: format, version_id: version_id)).once
      end

      it 'passes axe automated accessibility testing' do
        expect(find_by_testid('version-name')).to have_text(version_string)
        expect(find_by_testid('artifact-name')).to have_text(artifact_name)
        expect(page).to be_axe_clean.within_testid('repositories-shell').skipping :'link-in-text-block'
      end
    end

    context 'when landing on the Files tab' do
      before do
        visit "#{version_page_path}?tab=files"
      end

      it 'reads the version for both operations and lists the files', :aggregate_failures do
        within_testid('repositories-shell') do
          expect(find_by_testid('version-name')).to have_text(version_string)

          file_names.each do |file_name|
            expect(page).to have_css('[data-testid="file-name"]', text: file_name)
          end
        end

        expect(client).to have_received(:version)
          .with(slug: slug, repository_name: name, format: format, version_id: version_id).twice
        expect(client).to have_received(:version_statistics)
          .with(slug: slug, repository_name: name, format: format, version_id: version_id).once
        expect(client).to have_received(:version_files)
          .with(hash_including(slug: slug, repository_name: name, format: format, version_id: version_id)).once
      end
    end
  end

  describe 'a Maven version the schema resolves' do
    let(:name) { 'maven-repository' }
    let(:format) { 'maven' }
    let(:format_label) { 'Maven' }
    let(:version_string) { '3.2.1' }
    let(:artifact_name) { 'com.example.payments:payment-core' }
    let(:files_tab_title) { 'Files' }

    let(:package) do
      ::ArtifactRegistry::MavenPackage.new(
        'id' => artifact_id,
        'group_id' => 'com.example.payments',
        'artifact_id' => 'payment-core'
      )
    end

    let(:files) do
      [
        ::ArtifactRegistry::MavenFile.new(
          'id' => '01937b2e-0000-7000-8000-000000000201',
          'file_name' => 'payment-core-3.2.1.jar',
          'size' => 987_654,
          'sha256' => 'a' * 64,
          'sha1' => 'b' * 40,
          'sha512' => 'c' * 128,
          'md5' => 'd' * 32,
          'created_at' => '2026-06-10T00:00:00Z'
        ),
        ::ArtifactRegistry::MavenFile.new(
          'id' => '01937b2e-0000-7000-8000-000000000202',
          'file_name' => 'payment-core-3.2.1.pom',
          'size' => 2048,
          'sha256' => 'e' * 64,
          'sha1' => 'f' * 40,
          'sha512' => '9' * 128,
          'md5' => nil
        )
      ]
    end

    it 'carries the statistics files count on the Files tab' do
      visit version_page_path

      within_testid('repositories-shell') do
        expect(find_by_testid('version-name')).to have_text(version_string)

        within(find_link(files_tab_title)) do
          expect(find_by_testid('tab-counter-badge')).to have_text(files.size.to_s)
        end
      end
    end

    it_behaves_like 'a version the schema resolves'
  end

  describe 'an npm version the schema resolves' do
    let(:name) { 'npm-repository' }
    let(:format) { 'npm' }
    let(:format_label) { 'npm' }
    let(:version_string) { '1.4.0' }
    let(:artifact_name) { '@acme/ui-components' }
    let(:files_tab_title) { 'File' }

    let(:package) do
      ::ArtifactRegistry::NpmPackage.new(
        'id' => artifact_id,
        'name' => '@acme/ui-components',
        'scope' => '@acme'
      )
    end

    let(:files) do
      [
        ::ArtifactRegistry::NpmFile.new(
          'id' => '01937b2e-0000-7000-8000-000000000301',
          'file_name' => 'acme-ui-components-1.4.0.tgz',
          'size' => 524_288,
          'sha256' => 'a' * 64,
          'created_at' => '2026-06-10T00:00:00Z'
        )
      ]
    end

    it_behaves_like 'a version the schema resolves'
  end

  describe 'a version Artifact Registry does not hold' do
    let(:name) { 'maven-repository' }
    let(:format) { 'maven' }
    let(:version) { nil }

    let(:package) do
      ::ArtifactRegistry::MavenPackage.new(
        'id' => artifact_id,
        'group_id' => 'com.example.payments',
        'artifact_id' => 'payment-core'
      )
    end

    before do
      visit version_page_path
    end

    it 'renders the in-SPA not-found state' do
      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Page not found')
      end
    end
  end
end
