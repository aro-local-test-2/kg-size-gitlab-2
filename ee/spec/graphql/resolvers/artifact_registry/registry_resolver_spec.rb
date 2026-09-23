# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::ArtifactRegistry::RegistryResolver, feature_category: :artifact_registry do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: organization).user }

  specify { expect(described_class.type).to eq(::Types::ArtifactRegistry::RegistryType) }
  specify { expect(described_class.null).to be(true) }

  describe '#resolve' do
    subject(:resolve_registry) do
      resolve(described_class, obj: organization, ctx: { current_user: current_user })
    end

    context 'when the organization has no mapping row' do
      it 'returns nil without resolving a registry' do
        expect(organization.artifact_registry_namespace_mapping).to be_nil

        expect(resolve_registry).to be_nil
      end
    end

    context 'when the organization has a mapping row' do
      let_it_be(:mapping) do
        create(:artifact_registry_namespace_mapping, organization: organization)
      end

      before do
        allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
      end

      context 'when resolution succeeds' do
        let(:registry) do
          ::ArtifactRegistry::NamespaceMapping::Registry.new(
            slug: 'acme', status: 'active', created_at: Time.current
          )
        end

        it 'presents the resolved registry with the organization its permissions block reads through',
          :aggregate_failures do
          allow(mapping).to receive(:registry).and_return(registry)

          presented = resolve_registry

          expect(presented).to be_a(ArtifactRegistry::RegistryPresenter)
          expect(presented.organization).to be(organization)
          expect(presented.__subject__).to be(registry)
        end
      end

      context 'when resolution failed with an authorization error' do
        before do
          allow(mapping).to receive(:registry).and_return(
            ::ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(
              error_class: 'ArtifactRegistry::Client::AuthorizationError', status: 403
            )
          )
        end

        it 'resolves null rather than returning the failure marker' do
          expect(resolve_registry).to be_nil
        end
      end

      context 'when resolution failed with an unavailability error' do
        before do
          allow(mapping).to receive(:registry).and_return(
            ::ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(
              error_class: 'ArtifactRegistry::Client::UnavailableError', status: 503, request_id: 'req-1'
            )
          )
        end

        it 'resolves to the service-unavailable GraphQL error carrying the request ID' do
          result = resolve_registry

          expect(result).to be_a(::Gitlab::Graphql::Errors::ArtifactRegistry::ServiceUnavailable)
          expect(result.extensions).to include(request_id: 'req-1')
        end
      end

      context 'when resolution failed with an API error' do
        before do
          allow(mapping).to receive(:registry).and_return(
            ::ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(
              error_class: 'ArtifactRegistry::Client::ApiError', status: 400, code: 'invalid', request_id: 'req-2'
            )
          )
        end

        it 'surfaces an API error carrying the code and request ID' do
          result = resolve_registry

          expect(result).to be_a(::Gitlab::Graphql::Errors::BaseError)
          expect(result.extensions).to include(code: 'invalid', request_id: 'req-2')
        end
      end
    end
  end
end
