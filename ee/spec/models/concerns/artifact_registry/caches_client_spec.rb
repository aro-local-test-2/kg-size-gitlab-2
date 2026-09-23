# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::CachesClient, feature_category: :artifact_registry do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }

  let(:resource_class) do
    Class.new do
      include ArtifactRegistry::CachesClient
    end
  end

  let(:resource) { resource_class.new }

  describe '#artifact_registry_client' do
    it 'builds the client bound to the current user' do
      expect(ArtifactRegistry::Client).to receive(:new)
        .with(current_user: user, organization: resource).and_call_original

      expect(resource.artifact_registry_client(current_user: user)).to be_a(ArtifactRegistry::Client)
    end

    it 'memoizes one client per user across calls (one client per request)' do
      first = resource.artifact_registry_client(current_user: user)
      second = resource.artifact_registry_client(current_user: user)

      expect(first).to be(second)
    end

    it 'builds a distinct client for a different principal' do
      first = resource.artifact_registry_client(current_user: user)
      second = resource.artifact_registry_client(current_user: other_user)

      expect(first).not_to be(second)
    end

    it 'builds a client carrying the functional token-exchange default', :aggregate_failures do
      # The production construction path passes no token_exchange:, so the
      # default collaborator is what must be functional. The behavioural proof
      # that a minted header reaches AR lives in the repositories request spec.
      expect(::ArtifactRegistry::TokenExchange).to receive(:new).and_call_original

      client = resource.artifact_registry_client(current_user: user)

      expect(client).to be_a(::ArtifactRegistry::Client)
    end
  end

  describe '#artifact_registry_service_client' do
    it 'builds a client with no principal' do
      expect(ArtifactRegistry::Client).to receive(:new)
        .with(current_user: nil, organization: resource).and_call_original

      expect(resource.artifact_registry_service_client).to be_a(ArtifactRegistry::Client)
    end

    it 'is a distinct client from a per-user one' do
      expect(resource.artifact_registry_service_client)
        .not_to be(resource.artifact_registry_client(current_user: user))
    end

    # This site passes no service_credential:, so the default provider is the
    # whole wiring: what it reads is what reaches AR.
    context 'when a service token is mounted' do
      let(:base_url) { 'https://artifact-registry.example.test' }
      let(:secret_file) { '/etc/gitlab/artifact-registry/.gitlab_artifact_registry_secret' }
      let(:uuid) { 'a1b2c3d4-0000-0000-0000-000000000000' }

      before do
        stub_config(artifact_registry: { api_url: base_url, service_token: { secret_file: secret_file } })
        stub_file_read(secret_file, content: "mounted-service-token\n")
      end

      it 'presents the mounted secret in the service-token header' do
        request = stub_request(:get, "#{base_url}/api/gitlab/v1/namespaces/#{uuid}")
          .with(headers: { ArtifactRegistry::Client::SERVICE_TOKEN_HEADER => 'mounted-service-token' })
          .to_return(
            status: 200,
            body: { 'id' => uuid }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        resource.artifact_registry_service_client.namespace(uuid: uuid)

        expect(request).to have_been_requested
      end
    end
  end
end
