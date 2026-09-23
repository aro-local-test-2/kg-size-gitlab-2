# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Settings::ArtifactRegistryHelper, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:organization) { build_stubbed(:organization) }

  describe '#artifact_registry_settings_app_data' do
    subject(:app_data) do
      Gitlab::Json::SafeParser.parse(helper.artifact_registry_settings_app_data(organization))
    end

    before do
      stub_config(artifact_registry: { api_url: 'https://artifact-registry.example.com' })
    end

    it 'carries the organization global ID and the client base URL, and no other key' do
      expect(app_data).to eq(
        'organization_gid' => organization.to_global_id.to_s,
        'client_base_url' => 'https://artifact-registry.example.com'
      )
    end

    context 'when the configuration names no usable credential-free origin' do
      where(:case_name, :artifact_registry_config) do
        'the instance configures no Artifact Registry' | {}
        'the value names no host'                      | { api_url: 'https://' }
        'the value embeds a credential'                | { api_url: 'https://user:pass@artifact-registry.example.com' }
      end

      with_them do
        before do
          stub_config(artifact_registry: artifact_registry_config)
        end

        it 'carries a null client base URL, so the section composes no registry URL' do
          expect(app_data).to eq(
            'organization_gid' => organization.to_global_id.to_s,
            'client_base_url' => nil
          )
        end
      end
    end
  end
end
