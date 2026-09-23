# frozen_string_literal: true

RSpec.shared_context 'with a resolved Artifact Registry handle' do
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

  let(:service_token) { 'ar-service-credential' }
  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}" }

  let(:namespace_body) do
    {
      'id' => namespace_mapping.ar_namespace_id,
      'slug' => slug,
      'status' => 'active',
      'created_at' => '2026-07-01T10:00:00Z'
    }
  end

  before do
    allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
      allow(credential).to receive(:token).and_return(service_token)
    end

    stub_request(:get, namespace_url)
      .to_return(status: 200, headers: json_headers, body: namespace_body.to_json)
  end
end
