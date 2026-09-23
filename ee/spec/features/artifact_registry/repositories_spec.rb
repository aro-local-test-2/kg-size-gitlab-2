# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry repositories SPA', :js, :with_current_organization,
  feature_category: :artifact_registry do
  let(:user) { create(:user, organizations: [current_organization]) }

  let(:slug) { 'acme' }
  let(:repositories_base_path) { "/o/#{current_organization.path}/-/artifact_registry/#{slug}/repositories" }
  let(:client) { instance_double(::ArtifactRegistry::Client) }

  let_it_be(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  # Resolution is covered over HTTP in the controller request spec; faking it at
  # the model boundary here keeps this browser test independent of the Artifact
  # Registry wire contract and Rails.cache.
  let(:registry) do
    ::ArtifactRegistry::NamespaceMapping::Registry.new(
      slug: slug, status: 'active', created_at: '2026-07-01T10:00:00Z'
    )
  end

  def verdicts(scope, read, allowed)
    actions = ::ArtifactRegistry::Permissions::Verdicts::ACTIONS_BY_SCOPE.fetch(scope)

    ::ArtifactRegistry::Permissions::Verdicts.new(actions.index_with(allowed), scope: scope, read: read, slug: slug)
  end

  def denied_verdicts(scope, read)
    verdicts(scope, read, false)
  end

  before do
    allow_next_found_instance_of(::ArtifactRegistry::NamespaceMapping) do |mapping|
      allow(mapping).to receive(:registry).and_return(registry)
    end

    sign_in(user)
  end

  it 'boots the Vue SPA shell on the resolved-slug repositories route' do
    visit repositories_base_path

    expect(page).to have_testid('repositories-shell')
  end

  it 'serves a deep unregistered sub-path via the Rails catch-all and renders the in-SPA NotFound fallback' do
    # The path reads as a repository name, so the route resolves and the page asks the server
    # whether that repository exists. Faking the client keeps the example independent of whether
    # an Artifact Registry is reachable, which decides between not-found and service-unavailable.
    allow(::ArtifactRegistry::Client).to receive(:new)
      .with(current_user: user, organization: current_organization).and_return(client)
    allow(client).to receive(:repository)
      .with(slug: slug, name: 'does-not-exist', include_permissions: anything).and_return(nil)

    visit "#{repositories_base_path}/does-not-exist"

    within_testid('repositories-shell') do
      expect(page).to have_css('h1', text: 'Page not found')
    end
  end

  describe 'the repositories list' do
    # Faked at the client rather than over HTTP: the wire format is the client's own contract,
    # and these examples are about what the connection renders in a browser.
    let(:repository_attributes) do
      {
        'id' => '01937b2e-0000-7000-8000-000000000010',
        'name' => 'maven-releases',
        'format' => 'maven',
        'kind' => 'hosted',
        'visibility' => 'private',
        'downloads_count' => 340,
        'size_bytes' => 2048,
        'last_updated_at' => '2026-07-02T11:30:00Z'
      }
    end

    let(:repositories_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::Repository.new(repository_attributes, verdicts(:repository, :repositories, true))
        ],
        permissions: verdicts(:namespace, :repositories, true)
      )
    end

    before do
      allow(::ArtifactRegistry::Client).to receive(:new)
        .with(current_user: user, organization: current_organization).and_return(client)
      allow(client).to receive(:repositories).and_return(repositories_page)
    end

    it 'renders the page the connection returns' do
      visit repositories_base_path

      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Repositories')
        expect(page).to have_link('maven-releases')
        expect(page).to have_content('Maven')
        expect(page).to have_content('Hosted')
        expect(page).to have_content('340')
        expect(page).to have_content('2.00 KiB')
      end
    end

    it 'renders the controls the verdicts allow' do
      visit repositories_base_path

      within_testid('repositories-shell') do
        expect(page).to have_button('New repository')
        expect(page).to have_button('More actions for maven-releases')
      end
    end

    describe 'with every verdict denied' do
      let(:repositories_page) do
        ::ArtifactRegistry::Page.new(
          nodes: [
            ::ArtifactRegistry::Repository.new(repository_attributes, denied_verdicts(:repository, :repositories))
          ],
          permissions: denied_verdicts(:namespace, :repositories)
        )
      end

      it 'renders the list without its gated controls and passes axe automated accessibility testing' do
        visit repositories_base_path

        within_testid('repositories-shell') do
          expect(page).to have_link('maven-releases')
          expect(page).to have_no_button('New repository')
          expect(page).to have_no_button('More actions for maven-releases')
        end

        expect(page).to be_axe_clean.within_testid('repositories-shell')
      end
    end

    it 'passes axe automated accessibility testing' do
      visit repositories_base_path

      expect(page).to have_link('maven-releases')
      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  # The single-repository read the detail page and the edit form share. A green Jest suite cannot
  # speak for these two: their repository leaves the browser as a GraphQL document and comes back
  # resolved by the schema, so nothing short of a rendered page says which layer answered.
  describe 'a repository the schema resolves' do
    let(:name) { 'oci-repository' }
    let(:description) { 'Build artifacts for the payments domain.' }

    let(:attributes) do
      {
        'id' => '01937b2e-0000-7000-8000-000000000010',
        'name' => name,
        'format' => 'maven',
        'kind' => 'hosted',
        'visibility' => 'private',
        'description' => description,
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

    let(:packages_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::MavenPackage.new(
            'id' => '01937b2e-0000-7000-8000-000000000001',
            'group_id' => 'com.example.payments',
            'artifact_id' => 'payment-core'
          ),
          ::ArtifactRegistry::MavenPackage.new(
            'id' => '01937b2e-0000-7000-8000-000000000002',
            'group_id' => 'com.example.payments',
            'artifact_id' => 'payment-api'
          )
        ]
      )
    end

    before do
      allow(::ArtifactRegistry::Client).to receive(:new)
        .with(current_user: user, organization: current_organization).and_return(client)
      allow(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: false).and_return(repository)
      allow(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: true)
        .and_return(::ArtifactRegistry::Repository.new(attributes, permissions))
      allow(client).to receive(:packages).and_return(packages_page)
    end

    # The name deliberately says one format while the repository carries another, because the
    # front end guesses a format from the name wherever no read has resolved one. A page
    # rendering OCI here is one answering from that guess.
    it 'renders the detail page from the repository, not from the name' do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(find_by_testid('repository-name')).to have_text(name)
        expect(find_by_testid('repository-format-name', visible: :all)).to have_text(:all, 'Maven')
        expect(page).to have_css('[data-testid="repository-visibility"][aria-label="Private"]')
        expect(find_by_testid('repository-description')).to have_text(description)
        expect(page).to have_content('Hosted')
      end
    end

    it 'renders the artifact page the packages connection returns' do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(page).to have_link('com.example.payments:payment-core')
        expect(page).to have_link('com.example.payments:payment-api')
        expect(page).to have_button('More actions for com.example.payments:payment-core')
        expect(page).to have_button('Copy package name', count: 2)
        expect(find_by_testid('artifacts-announcement', visible: :all))
          .to have_text(:all, 'Artifact list updated.')
      end
    end

    # Visibility is left out: the closed beta offers the single Private value, so its radio is
    # selected whether the read answered or not.
    it 'prefills the edit form from the repository' do
      allow(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: true)
        .and_return(::ArtifactRegistry::Repository.new(attributes, permissions))

      visit "#{repositories_base_path}/#{name}/edit"

      within_testid('repositories-shell') do
        expect(page).to have_field(with: name, readonly: true)
        expect(page).to have_field(with: description, type: 'textarea')
        expect(page).to have_css('[data-testid="repository-format-logo"][src*="maven"]')
      end
    end
  end

  describe 'a virtual repository the schema resolves' do
    let(:name) { 'maven-virtual' }

    let(:attributes) do
      {
        'id' => '01937b2e-0000-7000-8000-000000000020',
        'name' => name,
        'format' => 'maven',
        'kind' => 'virtual',
        'visibility' => 'private',
        'description' => 'Resolves through the Maven upstreams.',
        'artifacts_count' => 0,
        'downloads_count' => 0,
        'size_bytes' => 0,
        'created_at' => '2026-05-12T09:24:00Z',
        'last_updated_at' => '2026-07-02T11:30:00Z'
      }
    end

    let(:permissions) do
      ::ArtifactRegistry::Permissions::Verdicts.new(
        ::ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true),
        scope: :repository, read: :repository, slug: slug
      )
    end

    let(:upstream_repositories) do
      [
        ::ArtifactRegistry::UpstreamRepositoryAssociation.new(
          'id' => 'a1000000-0000-4000-8000-000000000001',
          'position' => 1,
          'upstream_repository' => {
            'id' => 'd1000000-0000-4000-8000-000000000001',
            'name' => 'maven-central-proxy',
            'format' => 'maven',
            'kind' => 'remote'
          }
        ),
        ::ArtifactRegistry::UpstreamRepositoryAssociation.new(
          'id' => 'a1000000-0000-4000-8000-000000000002',
          'position' => 2,
          'upstream_repository' => {
            'id' => 'd1000000-0000-4000-8000-000000000002',
            'name' => 'payments-releases',
            'format' => 'maven',
            'kind' => 'hosted'
          }
        )
      ]
    end

    before do
      allow(::ArtifactRegistry::Client).to receive(:new)
        .with(current_user: user, organization: current_organization).and_return(client)
      allow(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: false).and_return(
          ::ArtifactRegistry::Repository.new(attributes)
        )
      allow(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: true).and_return(
          ::ArtifactRegistry::Repository.new(attributes, permissions)
        )
      allow(client).to receive(:upstream_repositories)
        .with(slug: slug, repository_name: name, format: 'maven').and_return(upstream_repositories)
    end

    it 'renders the upstream table and passes axe automated accessibility testing', :aggregate_failures do
      expect(client).not_to receive(:packages)

      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(page).to have_testid('upstream-name', count: 2)

        expect(all_by_testid('upstream-position').map(&:text)).to eq(%w[1 2])
        expect(all_by_testid('upstream-name').map(&:text))
          .to eq(%w[maven-central-proxy payments-releases])
        expect(all_by_testid('upstream-kind').map(&:text)).to eq(%w[Remote Hosted])

        expect(find_by_testid('repository-stat-repositories')).to have_text('2 Repositories')
      end

      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  describe 'with every verdict denied' do
    let(:name) { 'maven-releases' }

    let(:repository) do
      ::ArtifactRegistry::Repository.new(
        {
          'id' => '01937b2e-0000-7000-8000-000000000010',
          'name' => name,
          'format' => 'maven',
          'kind' => 'hosted',
          'visibility' => 'private',
          'artifacts_count' => 1,
          'downloads_count' => 340,
          'size_bytes' => 2048,
          'created_at' => '2026-05-12T09:24:00Z',
          'last_updated_at' => '2026-07-02T11:30:00Z'
        },
        denied_verdicts(:repository, :repository)
      )
    end

    let(:packages_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::MavenPackage.new(
            'id' => '01937b2e-0000-7000-8000-000000000001',
            'group_id' => 'com.example.payments',
            'artifact_id' => 'payment-core'
          )
        ]
      )
    end

    before do
      allow(::ArtifactRegistry::Client).to receive(:new)
        .with(current_user: user, organization: current_organization).and_return(client)
      allow(client).to receive(:packages).and_return(packages_page)
      allow(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: anything).and_return(repository)
    end

    it 'renders the detail without its gated controls and passes axe automated accessibility testing' do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(page).to have_link('com.example.payments:payment-core')
        expect(page).to have_no_link('Edit')
        expect(page).to have_no_button('More actions for com.example.payments:payment-core')
        expect(page).to have_button('Copy package name')
      end

      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  # The artifact route reads the same single repository, so whether it exists is Artifact
  # Registry's answer rather than the URL's. A page that rendered without asking would tell a
  # viewer a repository they cannot see is there. Nothing is asserted about the artifact itself,
  # which the browser still resolves for itself.
  describe 'an artifact of a repository Artifact Registry does not hold' do
    let(:name) { 'no-such-repository' }
    let(:artifact_id) { '01937b2e-0000-7000-8000-000000000001' }

    before do
      allow(::ArtifactRegistry::Client).to receive(:new)
        .with(current_user: user, organization: current_organization).and_return(client)
    end

    it 'asks Artifact Registry for the repository and renders its not-found state' do
      expect(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: true).at_least(:once).and_return(nil)

      visit "#{repositories_base_path}/#{name}/#{artifact_id}"

      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Page not found')
      end
    end
  end
end
