# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::ArtifactRegistryHelper, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  # The helper reads the organization's global ID and its path for the route, and writes
  # nothing, so it needs no persisted record.
  let(:organization) { build_stubbed(:organization) }
  let(:slug) { 'resolved-handle' }

  describe '#artifact_registry_repositories_app_data' do
    subject(:app_data) do
      Gitlab::Json::SafeParser.parse(
        helper.artifact_registry_repositories_app_data(organization, slug)
      )
    end

    it 'carries the organization global ID, the slug, the SPA base path, and the client base URL' do
      stub_config(artifact_registry: { api_url: 'https://artifact-registry.example.com' })

      expect(app_data).to eq(
        'organization_gid' => organization.to_global_id.to_s,
        'slug' => slug,
        'base_path' => helper.artifact_registry_repositories_organization_path(organization, slug),
        'client_base_url' => 'https://artifact-registry.example.com'
      )
    end

    describe 'the client base URL' do
      let(:artifact_registry_config) { { api_url: api_url } }

      before do
        stub_config(artifact_registry: artifact_registry_config)
      end

      context 'when no usable origin is configured' do
        where(:case_name, :api_url) do
          'the instance configures no Artifact Registry' | nil
          'the value names a scheme no client speaks'    | 'ftp://artifact-registry.example.com'
          'the value names no host'                      | 'https://'
          'the value embeds a credential'                | 'https://user:pass@artifact-registry.example.com'
        end

        with_them do
          it { expect(app_data['client_base_url']).to be_nil }
        end
      end

      # `api_url` has no production default, so the key can be absent outright. Reading it
      # must not raise on a view that renders on every repositories page.
      context 'when the api_url key is not set at all' do
        let(:artifact_registry_config) { {} }

        it { expect(app_data['client_base_url']).to be_nil }
      end
    end
  end

  describe '#artifact_registry_setup_app_data' do
    subject(:app_data) do
      Gitlab::Json::SafeParser.parse(helper.artifact_registry_setup_app_data(organization))
    end

    before do
      stub_config(artifact_registry: { api_url: 'https://artifact-registry.example.com' })
    end

    it 'carries the organization path and the client base URL, and no other key' do
      expect(app_data).to eq(
        'organization_path' => organization.path,
        'client_base_url' => 'https://artifact-registry.example.com'
      )
    end
  end
end
