# frozen_string_literal: true

require 'spec_helper'

# The grant and revoke specs cover how each service names a parent end to end.
# This covers the seam they share, so the rule that nothing names a parent
# until AR has confirmed the resource is pinned in one place rather than only
# as a consequence of two service behaviours.
RSpec.describe Authz::ArtifactRegistry::BaseService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: organization) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

  let(:namespace_id) { namespace_mapping.ar_namespace_id }
  let(:resource_id) { Gitlab::Utils.uuid_v7 }
  let(:ar_client) { instance_double(ArtifactRegistry::Client) }
  let(:submitted_resource_ids) { [resource_id] }

  # A minimal subclass, so the seam is exercised without either real service's
  # validation in the way. Only submitted_resource_ids is required of it.
  let(:service_class) do
    Class.new(described_class) do
      def initialize(current_user:, organization:, resource_ids:)
        @current_user = current_user
        @organization = organization
        @resource_ids = resource_ids
      end

      # Public so the spec can drive the seam directly.
      def parent_for(resource_id)
        verified_ancestor_for(resource_id)
      end

      private

      attr_reader :resource_ids

      alias_method :submitted_resource_ids, :resource_ids
    end
  end

  let(:service) do
    service_class.new(current_user: current_user, organization: organization, resource_ids: submitted_resource_ids)
  end

  before do
    allow(ArtifactRegistry::Client).to receive(:new).and_return(ar_client)
    allow(ar_client).to receive(:verify_repositories).and_return([])
  end

  describe '#verified_ancestor_for' do
    context 'when AR confirms the repository belongs to the namespace' do
      it 'names the namespace as its parent' do
        expect(service.parent_for(resource_id)).to eq(namespace_id)
      end
    end

    context 'when AR says the repository does not belong to the namespace' do
      before do
        allow(ar_client).to receive(:verify_repositories).and_return([resource_id])
      end

      it 'names no parent, so IAM still requires a role on the repository itself' do
        expect(service.parent_for(resource_id)).to be_nil
      end
    end

    context 'when the resource is the namespace itself' do
      let(:submitted_resource_ids) { [namespace_id] }

      it 'names no parent and never asks AR', :aggregate_failures do
        expect(ar_client).not_to receive(:verify_repositories)

        expect(service.parent_for(namespace_id)).to be_nil
      end
    end

    context 'when the resource is the organization itself' do
      let(:submitted_resource_ids) { [organization.uuid] }

      it 'names no parent, since the namespace does not sit above the organization' do
        expect(service.parent_for(organization.uuid)).to be_nil
      end
    end

    context 'when the organization has no Artifact Registry namespace' do
      let_it_be(:other_organization) { create(:organization) }

      let(:service) do
        service_class.new(current_user: current_user, organization: other_organization, resource_ids: [resource_id])
      end

      it 'names no parent and never asks AR', :aggregate_failures do
        expect(ar_client).not_to receive(:verify_repositories)

        expect(service.parent_for(resource_id)).to be_nil
      end
    end

    it 'asks AR once however many resources are resolved' do
      other_resource_id = Gitlab::Utils.uuid_v7
      service = service_class.new(
        current_user: current_user, organization: organization, resource_ids: [resource_id, other_resource_id]
      )

      expect(ar_client).to receive(:verify_repositories).once.and_return([])

      service.parent_for(resource_id)
      service.parent_for(other_resource_id)
    end
  end

  describe '#on_verification_failure' do
    before do
      allow(ar_client).to receive(:verify_repositories).and_raise(ArtifactRegistry::Client::UnavailableError)
    end

    it 'raises by default, so a subclass that wants to fail closed inherits it' do
      expect { service.parent_for(resource_id) }.to raise_error(ArtifactRegistry::Client::UnavailableError)
    end

    context 'when a subclass chooses to carry on without a parent' do
      let(:service_class) do
        Class.new(described_class) do
          def initialize(current_user:, organization:, resource_ids:)
            @current_user = current_user
            @organization = organization
            @resource_ids = resource_ids
          end

          def parent_for(resource_id)
            verified_ancestor_for(resource_id)
          end

          private

          attr_reader :resource_ids

          alias_method :submitted_resource_ids, :resource_ids

          def on_verification_failure(_error)
            Set.new
          end
        end
      end

      it 'names no parent instead of raising' do
        expect(service.parent_for(resource_id)).to be_nil
      end
    end
  end

  describe '#submitted_resource_ids' do
    it 'is required of a subclass' do
      subclass = Class.new(described_class) do
        def initialize(organization:)
          @organization = organization
        end

        def candidates
          candidate_repository_ids
        end
      end

      expect { subclass.new(organization: organization).candidates }
        .to raise_error(NotImplementedError, /must implement #submitted_resource_ids/)
    end
  end
end
