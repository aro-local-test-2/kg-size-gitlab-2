# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::NamespacePermissionsResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  let(:slug) { 'resolved-handle' }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: 'active') }
  let(:presented_registry) { ArtifactRegistry::RegistryPresenter.new(registry, organization: organization) }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, registry: registry) }

  let(:permissions) do
    ArtifactRegistry::Permissions::Verdicts.new(
      ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS.index_with { true },
      scope: :namespace, read: :namespace_details, slug: slug
    )
  end

  let(:details) { ArtifactRegistry::NamespaceDetails.new({ 'slug' => slug }, permissions) }
  let(:client) { instance_double(ArtifactRegistry::Client, namespace_details: details) }

  before do
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(client)
    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
  end

  subject(:resolve_permissions) do
    resolve(described_class, obj: presented_registry, ctx: { current_user: current_user })
  end

  it 'resolves the namespace permissions block, non-null', :aggregate_failures do
    expect(described_class.type).to be_non_null
    expect(described_class.type.unwrap).to eq(::Types::PermissionTypes::ArtifactRegistry::Namespace)
  end

  it 'reads the namespace details as the user, asking for verdicts, and hands them to the block',
    :aggregate_failures do
    block = resolve_permissions

    expect(client).to have_received(:namespace_details).with(slug: slug, include_permissions: true)
    expect(block.verdicts).to be(permissions)
    expect(block.declaring_type).to eq('ArtifactRegistry')
  end

  context 'when Artifact Registry does not know the slug for this caller' do
    let(:details) { nil }

    it 'raises resource-not-available rather than handing the block no verdicts' do
      expect(resolve_permissions).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
    end
  end

  context 'when Artifact Registry rejects the read' do
    let(:status) { 403 }
    let(:authorization_error) do
      ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: status, request_id: 'req-1')
    end

    before do
      allow(client).to receive(:namespace_details).and_raise(authorization_error)
    end

    it 'renders the standard resource-not-available error, hiding the rejection', :aggregate_failures do
      error = resolve_permissions

      expect(error).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
      expect(error.message).to eq(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
    end

    context 'when the rejection carries no status' do
      let(:status) { nil }

      it 'renders service-unavailable with the request ID, and tracks the exception', :aggregate_failures do
        expect(::Gitlab::ErrorTracking).to receive(:log_exception).with(authorization_error)

        error = resolve_permissions

        expect(error).to be_a(Gitlab::Graphql::Errors::ArtifactRegistry::ServiceUnavailable)
        expect(error.message).to eq(s_('ArtifactRegistry|The Artifact Registry service is unavailable.'))
        expect(error.extensions).to eq({ request_id: 'req-1' })
      end
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'gates on the organization the presenter carries and makes no client call', :aggregate_failures do
      expect(resolve_permissions).to be_nil
      expect(client).not_to have_received(:namespace_details)
    end
  end
end
