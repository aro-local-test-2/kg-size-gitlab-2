# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ArtifactRegistry::GrantRoleAssignmentsService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

  let_it_be(:current_user) { create(:user, organization: organization) }
  let_it_be(:assignee_a) { create(:user, organization: organization) }
  let_it_be(:assignee_b) { create(:user, organization: organization) }

  let(:resource_id) { Gitlab::Utils.uuid_v7 }
  let(:token) { 'ar-token' }
  let(:client) { instance_double(Authn::IamService::UpdateRelationshipsClient) }
  let(:ar_client) { instance_double(ArtifactRegistry::Client) }
  let(:assignments) do
    [
      { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
      { assignee: assignee_b, resource_id: resource_id, role: :artifact_admin }
    ]
  end

  subject(:execute) do
    described_class.new(current_user: current_user, organization: organization, assignments: assignments).execute
  end

  before do
    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: token)
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)

    allow(Authn::IamService::UpdateRelationshipsClient).to receive(:new).and_return(client)
    allow(client).to receive(:grant_roles).and_return(::Gitlab::Iam::Update::V1::WriteRelationshipsResponse.new)

    allow(ArtifactRegistry::Client).to receive(:new).and_return(ar_client)
    allow(ar_client).to receive(:verify_repositories).and_return([])
  end

  context 'when all assignments are valid' do
    it 'writes every assignment in a single call and returns success', :aggregate_failures do
      expect(client).to receive(:grant_roles) do |inputs, organization_uuid:, token:|
        expect(token).to eq('ar-token')
        expect(organization_uuid).to eq(organization.uuid)
        expect(inputs.map { |i| i[:assignee_id] }).to match_array([assignee_a.id, assignee_b.id])
        expect(inputs.map { |i| i[:role_id] })
          .to match_array([Authz::ArtifactRegistry::Roles.uuid_for(:artifact_viewer),
            Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin)])
        expect(inputs).to all(include(resource_id: resource_id))

        ::Gitlab::Iam::Update::V1::WriteRelationshipsResponse.new
      end

      result = execute
      expect(result).to be_success
      expect(result.payload[:granted_role_count]).to eq(2)
    end
  end

  context 'when there is no current user' do
    let(:current_user) { nil }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('signed in')
    end
  end

  context 'when the organization could not be determined' do
    let(:organization) { nil }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('Organization')
    end
  end

  describe 'the parent named on each object' do
    it 'names the namespace for a repository, so a namespace admin is accepted' do
      expect(client).to receive(:grant_roles) do |inputs, **|
        expect(inputs).to all(include(parent_id: namespace_mapping.ar_namespace_id))
      end

      expect(execute).to be_success
    end

    context 'when the assignment targets the namespace itself' do
      let(:assignments) do
        [{ assignee: assignee_a, resource_id: namespace_mapping.ar_namespace_id, role: :artifact_viewer }]
      end

      it 'names no parent, since an admin there holds the role on the object' do
        expect(client).to receive(:grant_roles) do |inputs, **|
          expect(inputs.first[:parent_id]).to be_nil
        end

        expect(execute).to be_success
      end
    end

    context 'when the organization has no Artifact Registry namespace' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:current_user) { create(:user, organization: organization) }
      let_it_be(:assignee_a) { create(:user, organization: organization) }

      let(:assignments) do
        [{ assignee: assignee_a, resource_id: namespace_mapping.ar_namespace_id, role: :artifact_viewer }]
      end

      it 'names no parent rather than raising' do
        expect(client).not_to receive(:grant_roles)

        expect(execute).to be_error
      end
    end
  end

  context 'when the caller is not a member of the organization' do
    let_it_be(:organization) { create(:organization) }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('another organization')
    end
  end

  # The case that was broken. Accounts stay owned by the default organization
  # while gaining membership of the organizations their groups move into, so a
  # caller granting in a promoted organization is never owned by it.
  context 'when the caller is a member of the organization but not owned by it' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }
    let_it_be(:current_user) { create(:user) }
    let_it_be(:assignee_a) { create(:user) }

    let(:assignments) do
      [{ assignee: assignee_a, resource_id: namespace_mapping.ar_namespace_id, role: :artifact_viewer }]
    end

    before do
      create(:organization_user, organization: organization, user: current_user)
      create(:organization_user, organization: organization, user: assignee_a)
    end

    it 'grants the role', :aggregate_failures do
      expect(current_user.organization_id).not_to eq(organization.id)
      expect(client).to receive(:grant_roles)

      expect(execute).to be_success
    end

    it 'mints the token for that organization, not the caller\'s own' do
      expect(Authn::TokenExchange::TokenIssuer).to receive(:new)
        .with(hash_including(organization: organization))
        .and_return(instance_double(Authn::TokenExchange::TokenIssuer, token: token))

      expect(execute).to be_success
    end

    context 'when the assignee is not a member of that organization' do
      before do
        Organizations::OrganizationUser.find_by(organization: organization, user: assignee_a).destroy!
      end

      it 'returns the generic not-found error and writes nothing', :aggregate_failures do
        expect(client).not_to receive(:grant_roles)

        result = execute
        expect(result).to be_error
        expect(result.message).to include('Assignee could not be found')
      end
    end
  end

  context 'when no assignments are given' do
    let(:assignments) { [] }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('At least one')
    end
  end

  context 'when one assignee belongs to a different organization' do
    let_it_be(:other_org_user) { create(:user, organization: create(:organization)) }

    let(:assignments) do
      [
        { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
        { assignee: other_org_user, resource_id: resource_id, role: :artifact_viewer }
      ]
    end

    it 'writes nothing and returns the generic not-found error', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('could not be found')
    end
  end

  context 'when one assignee is nil (user not found)' do
    let(:assignments) do
      [{ assignee: nil, resource_id: resource_id, role: :artifact_viewer }]
    end

    it 'writes nothing and returns the generic not-found error', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('could not be found')
    end
  end

  context 'when one resource_id is not a valid UUID' do
    let(:assignments) do
      [{ assignee: assignee_a, resource_id: 'not-a-uuid', role: :artifact_viewer }]
    end

    it 'writes nothing and returns the bare message without a position prefix', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('UUIDv7')
      expect(result.message).not_to include('Assignment ')
    end
  end

  # IAM only accepts UUIDv7 ids, so any other version is rejected here with a
  # precise message rather than failing at IAM with a generic invalid-request
  # error.
  context 'when one resource_id is a UUIDv4' do
    let(:assignments) do
      [{ assignee: assignee_a, resource_id: 'c7a3b3f4-9d3a-4e46-9c3e-3a1f0b2d4e5f', role: :artifact_viewer }]
    end

    it 'writes nothing and returns an error', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('UUIDv7')
    end
  end

  # IAM only accepts canonical lowercase ids, so the service normalizes case
  # instead of rejecting an uppercase id.
  context 'when one resource_id is an uppercase UUIDv7' do
    let(:assignments) do
      [{ assignee: assignee_a, resource_id: resource_id.upcase, role: :artifact_viewer }]
    end

    it 'downcases the id before writing it', :aggregate_failures do
      expect(client).to receive(:grant_roles) do |inputs, **_kwargs|
        expect(inputs).to all(include(resource_id: resource_id))

        ::Gitlab::Iam::Update::V1::WriteRelationshipsResponse.new
      end

      expect(execute).to be_success
    end
  end

  context 'when one role is unknown' do
    let(:assignments) do
      [{ assignee: assignee_a, resource_id: resource_id, role: :not_a_role }]
    end

    it 'writes nothing and returns an error', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('Unknown Artifact Registry role')
    end
  end

  context 'when several assignments are invalid for different reasons' do
    let(:assignments) do
      [
        { assignee: assignee_a, resource_id: 'not-a-uuid', role: :artifact_viewer },
        { assignee: assignee_b, resource_id: resource_id, role: :not_a_role }
      ]
    end

    it 'reports every validation error, identified by position', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('Assignment 1 on resource not-a-uuid', 'UUIDv7')
      expect(result.message).to include("Assignment 2 on resource #{resource_id}", 'Unknown Artifact Registry role')
    end
  end

  context 'when an assignee is listed twice for the same resource' do
    let(:assignments) do
      [
        { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
        { assignee: assignee_a, resource_id: resource_id, role: :artifact_admin }
      ]
    end

    it 'writes nothing and returns an error naming the assignee, resource, and roles', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('more than once')
      expect(result.message).to include(assignee_a.to_global_id.to_s)
      expect(result.message).to include(resource_id)
      expect(result.message).to include('ARTIFACT_VIEWER', 'ARTIFACT_ADMIN')
    end
  end

  context 'when several assignees are each duplicated' do
    let(:assignments) do
      [
        { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
        { assignee: assignee_a, resource_id: resource_id, role: :artifact_admin },
        { assignee: assignee_b, resource_id: resource_id, role: :artifact_viewer },
        { assignee: assignee_b, resource_id: resource_id, role: :artifact_contributor }
      ]
    end

    it 'lists every duplicated assignee in the error', :aggregate_failures do
      expect(client).not_to receive(:grant_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include(assignee_a.to_global_id.to_s)
      expect(result.message).to include(assignee_b.to_global_id.to_s)
    end
  end

  context 'when an assignee is granted on two different resources' do
    let(:other_resource_id) { Gitlab::Utils.uuid_v7 }
    let(:assignments) do
      [
        { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
        { assignee: assignee_a, resource_id: other_resource_id, role: :artifact_admin }
      ]
    end

    it 'is allowed and writes both' do
      expect(client).to receive(:grant_roles)

      expect(execute).to be_success
    end
  end

  describe 'resource verification' do
    it 'never builds a batch beyond the verification cap' do
      # The GraphQL layer caps a bulk grant at MAX_ARRAY_SIZE assignments, so
      # the distinct repository ids passed to verify_repositories stay within
      # the client's batch bound and its ArgumentError guard is unreachable.
      expect(::Types::BaseArgument::MAX_ARRAY_SIZE)
        .to be <= ::ArtifactRegistry::Client::MAX_VERIFICATION_BATCH
    end

    context 'when the organization has no AR namespace mapping' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:current_user) { create(:user, organization: organization) }

      let(:assignments) do
        [{ assignee: current_user, resource_id: resource_id, role: :artifact_viewer }]
      end

      it 'fails closed without calling AR or IAM', :aggregate_failures do
        expect(ar_client).not_to receive(:verify_repositories)
        expect(client).not_to receive(:grant_roles)

        result = execute
        expect(result).to be_error
        expect(result.message).to include('not available for this organization')
      end
    end

    context 'when every assignment targets the mapped namespace' do
      let(:assignments) do
        [{ assignee: assignee_a, resource_id: namespace_mapping.ar_namespace_id, role: :artifact_viewer }]
      end

      it 'verifies locally and never calls AR' do
        expect(ar_client).not_to receive(:verify_repositories)
        expect(client).to receive(:grant_roles)

        expect(execute).to be_success
      end
    end

    context 'when assignments target repositories' do
      let(:other_resource_id) { Gitlab::Utils.uuid_v7 }
      let(:assignments) do
        [
          { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
          { assignee: assignee_b, resource_id: resource_id, role: :artifact_admin },
          { assignee: assignee_a, resource_id: other_resource_id, role: :artifact_viewer },
          { assignee: assignee_b, resource_id: namespace_mapping.ar_namespace_id, role: :artifact_viewer }
        ]
      end

      it 'verifies the deduplicated repository ids, excluding the namespace', :aggregate_failures do
        expect(ar_client).to receive(:verify_repositories).with(
          namespace_id: namespace_mapping.ar_namespace_id,
          repository_ids: match_array([resource_id, other_resource_id])
        ).and_return([])
        expect(client).to receive(:grant_roles)

        expect(execute).to be_success
      end

      it 'reports each assignment on a failing resource by position and writes nothing', :aggregate_failures do
        allow(ar_client).to receive(:verify_repositories).and_return([resource_id])
        expect(client).not_to receive(:grant_roles)

        result = execute
        expect(result).to be_error
        expect(result.message).to include("Assignment 1 on resource #{resource_id}", 'could not be found')
        expect(result.message).to include("Assignment 2 on resource #{resource_id}")
        expect(result.message).not_to include('Assignment 3')
        expect(result.message).not_to include('Assignment 4')
      end

      # Every Client::Error subclass reaches this rescue: verify_repositories
      # re-raises anything that is not a 422, and AuthorizationError is a
      # sibling of UnavailableError rather than a subclass. Narrowing the rescue
      # to one of them would turn the other two into a 500.
      {
        'an outage' => ArtifactRegistry::Client::UnavailableError.new('down', status: 503),
        # ServiceCredential#token is nil until the service token is wired, so
        # this is the path every repository-targeted grant takes today.
        'a missing service credential' => ArtifactRegistry::Client::AuthorizationError.new('no credential'),
        # Drift between the mapping row and the namespace AR holds.
        'an unknown namespace' => ArtifactRegistry::Client::ApiError.new('gone', status: 404)
      }.each do |label, error|
        it "fails closed on #{label}", :aggregate_failures do
          allow(ar_client).to receive(:verify_repositories).and_raise(error)
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)
          expect(client).not_to receive(:grant_roles)

          result = execute
          expect(result).to be_error
          expect(result.message).to include('service is unavailable')
        end
      end

      # The client's input guards raise ArgumentError, which is outside
      # Client::Error. Without the rescue covering it this reaches the caller as
      # a 500 rather than a refusal.
      it 'fails closed when the client rejects its input', :aggregate_failures do
        allow(ar_client).to receive(:verify_repositories)
          .and_raise(ArgumentError, 'namespace_id must be a canonical UUID')
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(ArgumentError))
        expect(client).not_to receive(:grant_roles)

        result = execute
        expect(result).to be_error
        expect(result.message).to include('service is unavailable')
      end
    end

    # Guaranteed away by the client's details & submitted intersection, so this
    # holds the service against a collaborator that stops honouring it. Both
    # arities, because the two validation_error branches failed differently: a
    # single assignment raised NoMethodError on nil, a bulk one reported a blank
    # message.
    context 'when the verdict names no submitted resource' do
      let(:stray_id) { Gitlab::Utils.uuid_v7 }

      before do
        allow(ar_client).to receive(:verify_repositories).and_return([stray_id])
      end

      context 'with a single assignment' do
        let(:assignments) do
          [{ assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer }]
        end

        it 'fails closed on the unreadable verdict', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_object_having_attributes(
              class: ArtifactRegistry::Client::UnavailableError,
              message: /named no submitted resource/
            ))
          expect(client).not_to receive(:grant_roles)

          result = execute
          expect(result).to be_error
          expect(result.message).to include('service is unavailable')
        end
      end

      context 'with several assignments' do
        it 'fails closed rather than reporting a blank message', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_object_having_attributes(
              class: ArtifactRegistry::Client::UnavailableError,
              message: /named no submitted resource/
            ))
          expect(client).not_to receive(:grant_roles)

          result = execute
          expect(result).to be_error
          expect(result.message).to include('service is unavailable')
        end
      end
    end

    # assignment_error runs before verification. That ordering is what keeps the
    # client's UUIDv7 guard on repository_ids unreachable from user input, so a
    # malformed id can never reach it as an ArgumentError.
    context 'when an assignment is invalid' do
      let(:assignments) do
        [
          { assignee: assignee_a, resource_id: resource_id, role: :artifact_viewer },
          { assignee: assignee_b, resource_id: 'not-a-uuid', role: :artifact_viewer }
        ]
      end

      it 'reports the invalid assignment without contacting AR', :aggregate_failures do
        expect(ar_client).not_to receive(:verify_repositories)
        expect(client).not_to receive(:grant_roles)

        result = execute
        expect(result).to be_error
        expect(result.message).to include('must be a valid UUIDv7')
      end
    end
  end

  context 'when IAM returns an error' do
    {
      permission_denied: s_('ArtifactRegistry|You are not authorized to grant this role on this resource.'),
      unauthenticated: s_('ArtifactRegistry|Could not authenticate with the Artifact Registry service.'),
      invalid_request: s_('ArtifactRegistry|The role assignment request was invalid.'),
      unavailable: s_('ArtifactRegistry|The Artifact Registry service is unavailable.'),
      timeout: s_('ArtifactRegistry|The Artifact Registry service did not respond in time.'),
      unknown: s_('ArtifactRegistry|The role assignment could not be completed.')
    }.each do |reason, expected_message|
      context "with the #{reason} reason" do
        before do
          allow(client).to receive(:grant_roles).and_raise(
            Authn::IamService::UpdateRelationshipsClient::RequestError.new('diagnostic', reason: reason)
          )
        end

        it 'returns a service error with the mapped message and reason', :aggregate_failures do
          result = execute

          expect(result).to be_error
          expect(result.message).to eq(expected_message)
          expect(result.reason).to eq(reason)
        end
      end
    end
  end
end
