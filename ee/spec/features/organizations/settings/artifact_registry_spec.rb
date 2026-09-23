# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry settings shell', :js, :with_current_organization,
  feature_category: :artifact_registry do
  let_it_be(:user) { create(:user, :organization_owner, organizations: [current_organization]) }

  # The page reports on an existing registry, so the route answers not found without the
  # organization's namespace mapping row.
  let_it_be(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  # Resolution is covered over HTTP in the resolver spec; faking it at the model
  # boundary here keeps this browser test independent of the Artifact Registry wire
  # contract and Rails.cache, as the sibling repositories feature spec does.
  # `created_at` is a Time, not a String: unlike the repositories route, this page reads
  # the field through GraphQL, and `Types::TimeType` calls `iso8601` on it.
  # `ar_namespace_id` comes from the row like every real builder does: the page selects
  # `id`, which is `null: false`, so a fake without it nulls the whole registry and the
  # section renders nothing.
  let(:registry) do
    ::ArtifactRegistry::NamespaceMapping::Registry.new(
      ar_namespace_id: mapping.ar_namespace_id,
      slug: 'acme', status: 'active', created_at: Time.zone.parse('2026-07-01T10:00:00Z')
    )
  end

  before do
    allow_next_found_instance_of(::ArtifactRegistry::NamespaceMapping) do |mapping|
      allow(mapping).to receive(:registry).and_return(registry)
    end

    sign_in(user)
  end

  it 'boots the Vue settings shell and renders the activation section' do
    visit artifact_registry_settings_organization_path(current_organization)

    expect(page).to have_content(s_('ArtifactRegistry|Activation'))
    expect(page).to have_content(
      s_('ArtifactRegistry|Control artifact registry access for this organization. When ' \
        'enabled, all projects and groups have access to a unified registry.')
    )
    expect_page_to_have_no_console_errors
  end

  describe 'the disable confirmation' do
    before do
      visit artifact_registry_settings_organization_path(current_organization)
    end

    # The section's action and the dialog's confirm button carry the same label, so the
    # lookup names the region it means rather than leaving the match to depend on which
    # of the two is rendered.
    def open_confirmation
      within_testid('artifact-registry-settings') do
        click_button s_('ArtifactRegistry|Disable Artifact Registry')
      end
    end

    it 'passes axe automated accessibility testing with the confirmation closed and open' do
      # The section reads the registry before it can offer an action, so the action is what
      # says the rendered state this scans has arrived.
      within_testid('artifact-registry-settings') do
        expect(page).to have_button(s_('ArtifactRegistry|Disable Artifact Registry'))
      end

      expect(page).to be_axe_clean.within_testid('artifact-registry-settings')

      open_confirmation

      expect(page).to have_css('[role="dialog"]')
      expect(page).to be_axe_clean.within('[role="dialog"]')
    end

    it 'takes focus, closes on Escape, and gives focus back to the action that opened it' do
      open_confirmation

      expect(page).to have_css('[data-testid="confirm-danger-field"]:focus')

      send_keys :escape

      expect(page).not_to have_css('[role="dialog"]')
      expect(page).to have_css('[data-testid="disable-registry"]:focus')
    end
  end
end
