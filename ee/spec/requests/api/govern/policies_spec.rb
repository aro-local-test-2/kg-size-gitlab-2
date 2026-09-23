# frozen_string_literal: true

require 'spec_helper'
require Rails.root.join('gems/gitlab-policy-store/spec/support/rego_program_helpers')

RSpec.describe API::Govern::Policies, :api, :aggregate_failures,
  feature_category: :security_policy_management do
  let_it_be(:user) { create(:user) }

  before do
    stub_licensed_features(security_orchestration_policies: true)
    stub_application_setting(policy_store_experiment_enabled: true)
  end

  include PolicyStoreRegoHelpers

  # `scope_rego` is parsed, so its at-limit value must be valid Rego.
  def at_limit_value(attribute, limit)
    attribute == :scope_rego ? scope_rego_of(limit) : 'a' * limit
  end

  shared_examples 'a policy store endpoint that maps forbidden to 403' do |service_class|
    context 'when the service reports forbidden' do
      before do
        allow_next_instance_of(service_class) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'You shall not pass', reason: :forbidden)
          )
        end
      end

      it 'returns 403 rather than tracking an unmapped reason' do
        expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

        perform_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end

  shared_examples 'a policy store endpoint that maps an engine fault to 500' do
    context 'when the engine fails while validating a rule' do
      before do
        allow(Gitlab::PolicyStore::RegoValidator).to receive(:validate!)
          .and_raise(Gitlab::PolicyStore::EngineError, 'rules[0] could not be validated')
      end

      it 'returns 500 with the message and tracks the fault' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(Gitlab::PolicyStore::EngineError), tracked_context)

        perform_request

        expect(response).to have_gitlab_http_status(:internal_server_error)
        expect(json_response['message']).to eq('rules[0] could not be validated')
      end
    end
  end

  shared_examples 'a policy store catalogue endpoint' do
    let(:current_user) { user }

    subject(:perform_request) { get api(path, current_user) }

    it 'returns the catalogue' do
      perform_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(expected_catalogue)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_policies_v2: false)
      end

      it 'returns 404, so the flag works as a kill switch on its own' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the experiment is disabled for the instance' do
      before do
        stub_application_setting(policy_store_experiment_enabled: false)
      end

      it 'returns 404' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the flag is enabled for one organization but not another' do
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:other_organization_user) { create(:user, organization: other_organization) }

      before do
        stub_feature_flags(security_policies_v2: [user.organization])
      end

      it 'returns the catalogue only for the enabled organization, proving the check is per-organization' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)

        get api(path, other_organization_user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the license is not available' do
      before do
        stub_licensed_features(security_orchestration_policies: false)
      end

      it 'returns 403' do
        perform_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      let(:current_user) { nil }

      it 'returns 404, since the organization is resolved from the caller' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the token is invalid' do
      it 'ignores the credentials rather than returning 401, and returns 404 like an unauthenticated request' do
        get api(path), headers: { 'PRIVATE-TOKEN' => 'not-a-real-token' }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user is blocked' do
      let(:current_user) { create(:user, :blocked, organization: user.organization) }

      it 'returns 404, since a blocked user is not a valid actor here either' do
        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when authenticating with a granular access token that has no relevant permission' do
      it 'returns 404, rather than letting an unscoped granular token pass straight through' do
        granular_token = create(:granular_pat, user: current_user)

        get api(path, personal_access_token: granular_token)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /security/policy_store/triggers' do
    it_behaves_like 'a policy store catalogue endpoint' do
      let(:path) { '/security/policy_store/triggers' }
      let(:expected_catalogue) do
        [
          { 'id' => 'deployment_requested', 'name' => 'Deployment requested' },
          { 'id' => 'environment_advanced', 'name' => 'Environment advanced' },
          { 'id' => 'deployment_promoted', 'name' => 'Deployment promoted' }
        ]
      end
    end
  end

  describe 'GET /security/policy_store/actions' do
    it_behaves_like 'a policy store catalogue endpoint' do
      let(:path) { '/security/policy_store/actions' }
      let(:expected_catalogue) do
        [
          { 'id' => 'block', 'name' => 'Block' },
          { 'id' => 'require_approval', 'name' => 'Require approval' }
        ]
      end
    end
  end

  describe 'GET /security/policy_store/rules' do
    it_behaves_like 'a policy store catalogue endpoint' do
      let(:path) { '/security/policy_store/rules' }
      let(:expected_catalogue) do
        [
          { 'id' => 'custom', 'name' => 'Custom' },
          { 'id' => 'calendar', 'name' => 'Calendar' },
          { 'id' => 'environment', 'name' => 'Environment' }
        ]
      end
    end
  end

  describe 'the organization-scoped routes', :policy_store do
    let_it_be(:organization) { create(:organization) }
    let(:current_user) { owner }
    let(:target_organization_id) { organization.id }
    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        name: 'Block deployments on critical findings',
        trigger_type: 'deployment_requested'
      )
    end

    let_it_be(:private_organization) { create(:organization, :private) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:owner) { create(:user) }
    let_it_be(:member) { create(:user) }

    subject(:perform_request) { get api(path, current_user) }

    def rules_merging_to(merged_bytesize)
      declaration = "#{Gitlab::PolicyStore::RegoPackage::RULE_PRELUDE}\n"
      empty_comment_line = "# \n"
      padding = 'p' * (merged_bytesize - declaration.bytesize - empty_comment_line.bytesize)

      [{ type: 'custom', value: "#{declaration}# #{padding}\n" }]
    end

    before_all do
      create(:organization_user, :owner, organization: organization, user: owner)
      create(:organization_user, organization: organization, user: member, access_level: :default)
    end

    before do
      [organization, private_organization, other_organization].each do |org|
        ::Organizations::OrganizationSetting.for(org.id).update!(policy_store_experiment_enabled: true)
      end
    end

    shared_examples 'an organization-scoped policy store endpoint' do
      let(:expected_success_status) { :ok }

      context 'when the user is an organization member without the owner role' do
        let(:current_user) { member }

        it 'returns 403' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when the user does not belong to the organization' do
        let(:current_user) { user }

        it 'returns 403, since the organization itself is public and readable' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when the organization is private and the user does not belong to it' do
        let(:current_user) { user }
        let(:target_organization_id) { private_organization.id }

        it 'returns 404 naming the organization, the same as one that does not exist' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Organization Not Found')
        end
      end

      context 'when the organization does not exist' do
        let(:target_organization_id) { non_existing_record_id }

        it 'returns 404 naming the organization' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Organization Not Found')
        end
      end

      context 'when the organization is private, unreadable, and the feature flag is disabled' do
        let(:current_user) { user }
        let(:target_organization_id) { private_organization.id }

        before do
          stub_feature_flags(security_policies_v2: false)
        end

        it 'returns 404 naming the organization, same as when it is readable but flag state is irrelevant' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Organization Not Found')
        end
      end

      context 'when the organization id is not numeric' do
        let(:target_organization_id) { 'not-a-number' }

        it 'returns 400 from parameter validation, before any organization lookup' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when unauthenticated' do
        let(:current_user) { nil }

        it 'returns 401, unlike the catalogue routes' do
          perform_request

          expect(response).to have_gitlab_http_status(:unauthorized)
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(security_policies_v2: false)
        end

        it 'returns 404 without naming a resource, so the gate reveals nothing about the route' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Not Found')
        end
      end

      context 'when the experiment is disabled for the instance' do
        before do
          stub_application_setting(policy_store_experiment_enabled: false)
        end

        it 'returns 404 without naming a resource, since it is a separate gate from the flag' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Not Found')
        end
      end

      context 'when the feature flag is enabled for this organization but not another' do
        let_it_be(:other_organization_owner) { create(:user) }

        before_all do
          create(:organization_user, :owner, organization: other_organization, user: other_organization_owner)
        end

        before do
          stub_feature_flags(security_policies_v2: [organization])
        end

        it 'still allows this organization through, proving the check is scoped to it, not the whole instance' do
          perform_request

          expect(response).to have_gitlab_http_status(expected_success_status)
        end

        it 'returns 404 for a different organization, since the flag is not enabled for it' do
          get api(path.sub(%r{/organizations/#{organization.id}/}, "/organizations/#{other_organization.id}/"),
            other_organization_owner)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the license is not available' do
        before do
          stub_licensed_features(security_orchestration_policies: false)
        end

        it 'returns 403' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end

    describe 'GET /organizations/:id/security/policy_store' do
      let(:path) { "/organizations/#{target_organization_id}/security/policy_store" }

      it 'returns the policies of the organization' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to contain_exactly(
          a_hash_including(
            'id' => policy.id,
            'organization_id' => organization.id,
            'name' => 'Block deployments on critical findings',
            'trigger_type' => 'deployment_requested',
            'version' => 1,
            'mode' => 'warn',
            'lifecycle_state' => 'active',
            'scope_dimensions' => []
          )
        )
      end

      it 'matches the policies schema' do
        perform_request

        expect(response).to match_response_schema('public_api/v4/govern_policies', dir: 'ee')
      end

      context 'with the persistent repository', :aggregate_failures do
        include_context 'with a persistent policy store'

        it 'does not grow with the number of policies on the page' do
          control = ActiveRecord::QueryRecorder.new(skip_cached: false) { get api(path, current_user) }

          create_policy(organization_id: organization.id, name: 'Another policy', trigger_type: 'deployment_requested')

          expect { get api(path, current_user) }.not_to exceed_all_query_limit(control)
        end
      end

      it 'sets the pagination headers, with no next page and no total', :aggregate_failures do
        perform_request

        expect(response.headers['X-Page']).to eq('1')
        expect(response.headers['X-Per-Page']).to eq(Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_PER_PAGE.to_s)
        expect(response.headers['X-Next-Page']).to eq('')
        expect(response.headers['X-Prev-Page']).to eq('')
        expect(response.headers['X-Total']).to be_nil
        expect(response.headers['X-Total-Pages']).to be_nil
      end

      context 'with more policies than fit on one page' do
        let(:path) do
          "/organizations/#{target_organization_id}/security/policy_store?per_page=1"
        end

        let!(:other_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Other policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'returns only the requested page and signals a next page', :aggregate_failures do
          perform_request

          expect(json_response.pluck('id')).to contain_exactly(policy.id)
          expect(response.headers['X-Next-Page']).to eq('2')
          expect(response.headers['X-Per-Page']).to eq('1')
        end

        it 'returns the next page on request, with no further page after it', :aggregate_failures do
          get api("#{path}&page=2", current_user)

          expect(json_response.pluck('id')).to contain_exactly(other_policy.id)
          expect(response.headers['X-Next-Page']).to eq('')
          expect(response.headers['X-Prev-Page']).to eq('1')
        end
      end

      context 'when per_page exceeds the maximum' do
        let(:path) do
          "/organizations/#{target_organization_id}/security/policy_store?per_page=1000"
        end

        it 'clamps to the maximum rather than the requested value' do
          perform_request

          expect(response.headers['X-Per-Page'])
            .to eq(Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE.to_s)
        end
      end

      context 'when page exceeds the maximum' do
        let(:path) do
          "/organizations/#{target_organization_id}/security/policy_store?page=1000000000"
        end

        it 'clamps to the maximum rather than computing an unbounded offset' do
          perform_request

          expect(response.headers['X-Page']).to eq(
            Security::SecurityOrchestrationPolicies::PolicyStore::ListService::MAX_PAGE.to_s
          )
        end
      end

      context 'with a negative page or per_page' do
        it 'returns 400 for a negative page' do
          get api("#{path}?page=-1", current_user)

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'returns 400 for a negative per_page' do
          get api("#{path}?per_page=-1", current_user)

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        context 'when only_positive_pagination_values is disabled' do
          before do
            stub_feature_flags(only_positive_pagination_values: false)
          end

          it 'clamps a negative page up to 1 instead of erroring', :aggregate_failures do
            get api("#{path}?page=-1", current_user)

            expect(response).to have_gitlab_http_status(:ok)
            expect(response.headers['X-Page']).to eq('1')
          end

          it 'clamps a negative per_page up to 1 instead of erroring', :aggregate_failures do
            get api("#{path}?per_page=-1", current_user)

            expect(response).to have_gitlab_http_status(:ok)
            expect(response.headers['X-Per-Page']).to eq('1')
          end
        end
      end

      context 'with a trigger_type' do
        let!(:promoted_deployment_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Promoted deployment policy',
            trigger_type: 'deployment_promoted'
          )
        end

        let(:path) do
          "/organizations/#{target_organization_id}/security/policy_store?trigger_type=deployment_requested"
        end

        it 'returns only the policies for that trigger' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.pluck('id')).to contain_exactly(policy.id)
        end

        context 'when the trigger is not in the catalogue' do
          let(:path) do
            "/organizations/#{target_organization_id}/security/policy_store?trigger_type=merge_request"
          end

          it 'returns 400, rather than an empty collection, since the route constrains the value' do
            perform_request

            expect(response).to have_gitlab_http_status(:bad_request)
          end
        end
      end

      context 'with lifecycle_state' do
        let!(:disabled_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Disabled policy',
            trigger_type: 'deployment_requested',
            lifecycle_state: 'disabled'
          )
        end

        it 'defaults to only the active policies' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.pluck('id')).to contain_exactly(policy.id)
        end

        context 'when lifecycle_state is disabled' do
          let(:path) { "/organizations/#{target_organization_id}/security/policy_store?lifecycle_state=disabled" }

          it 'returns only the disabled policies' do
            perform_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.pluck('id')).to contain_exactly(disabled_policy.id)
          end
        end

        context 'when lifecycle_state is active' do
          let(:path) { "/organizations/#{target_organization_id}/security/policy_store?lifecycle_state=active" }

          it 'matches the default and returns only the active policies' do
            perform_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.pluck('id')).to contain_exactly(policy.id)
          end
        end

        context 'when lifecycle_state is all' do
          let(:path) { "/organizations/#{target_organization_id}/security/policy_store?lifecycle_state=all" }

          it 'returns every policy in one request regardless of lifecycle state' do
            perform_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.pluck('id')).to contain_exactly(policy.id, disabled_policy.id)
          end
        end

        context 'when lifecycle_state is not one of the allowed values' do
          let(:path) { "/organizations/#{target_organization_id}/security/policy_store?lifecycle_state=bogus" }

          it 'returns 400 Bad Request' do
            perform_request

            expect(response).to have_gitlab_http_status(:bad_request)
          end
        end
      end

      context 'when another organization owns a policy' do
        let!(:other_organization_policy) do
          create_policy(
            organization_id: other_organization.id,
            name: 'Other organization policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'omits it, so a policy id alone does not cross organizations' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.pluck('id')).to contain_exactly(policy.id)
        end
      end

      context 'when the organization has no policies' do
        let_it_be(:empty_organization) { create(:organization) }

        let(:target_organization_id) { empty_organization.id }

        before_all do
          create(:organization_user, :owner, organization: empty_organization, user: owner)
        end

        before do
          ::Organizations::OrganizationSetting.for(empty_organization.id)
            .update!(policy_store_experiment_enabled: true)
        end

        it 'returns an empty collection' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq([])
        end
      end

      context 'when the service reports the experiment inactive' do
        before do
          allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'nope', reason: :experiment_not_active)
            )
          end
        end

        it 'returns 404 rather than presenting an empty payload' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the service reports invalid input' do
        before do
          allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Missing required attributes: name', reason: :invalid)
            )
          end
        end

        it 'returns 400 and forwards the message, since it is written for the caller' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Missing required attributes: name')
        end

        it 'does not track it, so a mapped reason cannot page anyone' do
          expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

          perform_request
        end
      end

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        ::Security::SecurityOrchestrationPolicies::PolicyStore::ListService

      context 'when the service fails for a reason the endpoint does not map' do
        before do
          allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'PG::ConnectionBad: could not connect to host', reason: :unexpected)
            )
          end
        end

        it 'returns 500 and a generic message, since the reason is a bug on our side' do
          perform_request

          expect(response).to have_gitlab_http_status(:internal_server_error)
          expect(json_response['message']).to eq('Could not complete the policy store request')
          expect(json_response['message']).not_to include('PG::ConnectionBad')
        end

        it 'tracks the reason as the title, so the tracked issue names the fix' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            having_attributes(
              class: ::API::Govern::Policies::UnmappedReasonError,
              message: 'Unmapped policy store reason: unexpected'
            ),
            service_message: 'PG::ConnectionBad: could not connect to host'
          )

          perform_request
        end
      end

      it_behaves_like 'an organization-scoped policy store endpoint'

      it_behaves_like 'authorizing granular token permissions', :read_govern_policy do
        let(:user) { owner }
        let(:boundary_object) { :instance }
        let(:request) { get api(path, personal_access_token: pat) }
      end
    end

    describe 'GET /organizations/:id/security/policy_store/:policy_id' do
      let(:target_policy_id) { policy.id }
      let(:path) { "/organizations/#{target_organization_id}/security/policy_store/#{target_policy_id}" }

      it 'returns the policy' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          'id' => policy.id,
          'organization_id' => organization.id,
          'name' => 'Block deployments on critical findings',
          'trigger_type' => 'deployment_requested',
          'version' => 1,
          'mode' => 'warn',
          'lifecycle_state' => 'active',
          'scope_dimensions' => []
        )
      end

      it 'matches the policy schema' do
        perform_request

        expect(response).to match_response_schema('public_api/v4/govern_policy', dir: 'ee')
      end

      context 'when a stored rule carries no compiled rego' do
        before do
          allow_next_instance_of(Gitlab::PolicyStore::RuleProgramMerger) do |merger|
            allow(merger).to receive(:merge)
              .and_raise(Gitlab::PolicyStore::Error, 'rule 0 has no compiled rego to merge')
          end
        end

        it 'renders the policy with policy_rego nil rather than failing the whole response' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['policy_rego']).to be_nil
        end

        it 'tracks the error, so a missing rego does not fail silently' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            having_attributes(message: 'rule 0 has no compiled rego to merge'), policy_id: policy.id
          )

          perform_request
        end
      end

      context 'when the policy does not exist' do
        let(:target_policy_id) { non_existing_record_id }

        it 'returns 404 naming the policy, not the organization it looked in' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      context 'when the policy belongs to another organization' do
        let(:target_policy_id) do
          create_policy(
            organization_id: other_organization.id,
            name: 'Other organization policy',
            trigger_type: 'deployment_requested'
          ).id
        end

        it 'returns the same 404 as a missing policy, so an id cannot be probed across organizations' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      it_behaves_like 'an organization-scoped policy store endpoint'

      it_behaves_like 'authorizing granular token permissions', :read_govern_policy do
        let(:user) { owner }
        let(:boundary_object) { :instance }
        let(:request) { get api(path, personal_access_token: pat) }
      end
    end

    describe 'POST /organizations/:id/security/policy_store' do
      let(:path) { "/organizations/#{target_organization_id}/security/policy_store" }

      let(:policy_params) do
        {
          name: 'Require approval on critical findings',
          trigger_type: 'deployment_requested',
          rules: [{ type: 'custom', value: 'package governance' }]
        }
      end

      subject(:perform_request) { post api(path, current_user), params: policy_params }

      it 'creates the policy and returns it' do
        expect { perform_request }
          .to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }.by(1)

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response).to include(
          'organization_id' => organization.id,
          'name' => 'Require approval on critical findings',
          'trigger_type' => 'deployment_requested',
          'version' => 1,
          'mode' => 'warn',
          'lifecycle_state' => 'active'
        )
        # Declaring the entry shape means declared_params rebuilds each rule, so assert the
        # stored rule still carries the authored keys, and the rego compiled from them.
        expect(json_response['rules'])
          .to eq([{ 'type' => 'custom', 'value' => 'package governance', 'rego' => 'package governance' }])
        expect(json_response['policy_rego']).to eq("package governance\n")
      end

      it 'matches the policy schema' do
        perform_request

        expect(response).to match_response_schema('public_api/v4/govern_policy', dir: 'ee')
      end

      context 'when a rule does not parse' do
        let(:broken_rule) { { type: 'custom', value: "package governance\n\nviolation contains {\"msg\": \"x\" if {" } }
        let(:policy_params) { super().merge(rules: [broken_rule]) }

        it 'returns 400 naming the rule and the location, and does not persist the policy' do
          expect { perform_request }
            .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to match(/\Arules\[0\] is invalid: .+ \(at 3:\d+\)\z/)
        end
      end

      context 'when an authored scope_rego does not parse' do
        let(:policy_params) { super().merge(scope_rego: "package gitlab.scope\n\napplies if {\n") }

        it 'returns 400 naming scope_rego and the location' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to match(/\Ascope_rego is invalid: .+ \(at \d+:\d+\)\z/)
        end
      end

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        ::Security::SecurityOrchestrationPolicies::PolicyStore::CreateService

      it_behaves_like 'a policy store endpoint that maps an engine fault to 500' do
        let(:tracked_context) { { organization_id: organization.id } }
      end

      context 'when the optional attributes are given rather than defaulted' do
        let(:policy_params) do
          super().merge(description: 'Only on critical findings', mode: 'audit', lifecycle_state: 'disabled')
        end

        it 'stores them instead of falling back to the defaults' do
          perform_request

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response).to include(
            'description' => 'Only on critical findings',
            'mode' => 'audit',
            'lifecycle_state' => 'disabled'
          )
        end
      end

      context 'when an enumerated attribute is outside the values it allows' do
        { mode: 'not_a_mode', lifecycle_state: 'not_a_state' }.each do |attribute, invalid_value|
          it "returns 400 for #{attribute}" do
            post api(path, current_user), params: policy_params.merge(attribute => invalid_value)

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['error']).to eq("#{attribute} does not have a valid value")
          end
        end
      end

      context 'when a free-form string is longer than the store accepts' do
        ::Gitlab::PolicyStore::Ports::PolicyRepository::TEXT_LIMITS.each do |attribute, limit|
          it "returns 400 for #{attribute}, so the payload is refused before the store parses it" do
            expect { post api(path, current_user), params: policy_params.merge(attribute => 'a' * (limit + 1)) }
              .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['error']).to include(attribute.to_s, "must be less than #{limit} characters")
          end

          it "accepts #{attribute} at exactly #{limit} characters" do
            post api(path, current_user), params: policy_params.merge(attribute => at_limit_value(attribute, limit))

            expect(response).to have_gitlab_http_status(:created)
          end
        end
      end

      context 'with a policy scope' do
        let(:policy_params) do
          super().merge(policy_scope: { compliance_frameworks: [{ id: 5 }] })
        end

        it 'compiles the scope into the returned program', :aggregate_failures do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['scope_rego']).to include('framework_id in {5}')
          expect(json_response['scope_dimensions']).to eq(['compliance_frameworks'])
        end
      end

      context 'without a policy scope' do
        it 'returns an empty scope_dimensions, since an unscoped policy reads nothing' do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['scope_dimensions']).to eq([])
        end
      end

      context 'with a hand-authored scope_rego' do
        let(:policy_params) { super().merge(scope_rego: "package gitlab.scope\n\n# hand written\napplies := true\n") }

        it 'returns nil scope_dimensions, since the paths cannot be derived from Rego' do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response).to have_key('scope_dimensions')
          expect(json_response['scope_dimensions']).to be_nil
        end
      end

      context 'when the trigger is not one the catalogue offers' do
        let(:policy_params) { super().merge(trigger_type: 'not_a_trigger') }

        it 'returns 400' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to eq('trigger_type does not have a valid value')
        end
      end

      context 'when a required attribute is missing' do
        let(:policy_params) { super().except(:name) }

        it 'returns 400 naming the attribute' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('name')
        end
      end

      # Both cases need a JSON body. Form encoding drops an empty array entirely and has no
      # way to send null, so neither value can reach the endpoint that way.
      context 'when rules is empty in a JSON body' do
        it 'returns 400, since a policy with no rules can never match' do
          post api(path, current_user), params: policy_params.merge(rules: []).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules')
        end
      end

      context 'when rules is null in a JSON body' do
        it 'returns 400 rather than raising, since a declared Array still arrives nil' do
          post api(path, current_user), params: policy_params.merge(rules: nil).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules')
        end
      end

      context 'when rules is a scalar in a JSON body' do
        [1.5, true, 'not-an-array'].each do |scalar|
          it "returns 400 rather than raising for #{scalar.inspect}" do
            post api(path, current_user), params: policy_params.merge(rules: scalar).to_json,
              headers: { 'Content-Type' => 'application/json' }

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['error']).to eq('rules is invalid')
          end
        end
      end

      context 'when a rules element is blank' do
        it 'returns 400 for a blank element in a form-encoded body' do
          expect { post api(path, current_user), params: policy_params.merge(rules: ['']) }
            .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules[0] is blank')
        end

        it 'returns 400 for an empty object in a JSON body' do
          expect do
            post api(path, current_user), params: policy_params.merge(rules: [{}]).to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules[0] is blank')
        end

        it 'returns 400 for an empty array, naming the position' do
          expect do
            post api(path, current_user), params: policy_params.merge(rules: [[]]).to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules[0] is blank')
        end

        it 'names every blank position, so a caller sending several rules can find them' do
          blank_and_valid = ['', { type: 'custom', value: 'package governance' }, {}]

          expect do
            post api(path, current_user), params: policy_params.merge(rules: blank_and_valid).to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules[0], rules[2] is blank')
        end
      end

      context 'when an actions element is blank' do
        it 'returns 400 rather than storing the blank element' do
          expect { post api(path, current_user), params: policy_params.merge(actions: ['']) }
            .not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('actions[0] is blank')
        end

        it 'returns 400 for an empty object in a JSON body' do
          expect do
            post api(path, current_user), params: policy_params.merge(actions: [{}]).to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('actions[0] is blank')
        end
      end

      context 'when rules carries more entries than the store accepts' do
        let(:limit) { ::Gitlab::PolicyStore::Ports::PolicyRepository::ENTRY_COUNT_LIMITS[:rules] }

        it 'returns 400 naming the attribute and the limit' do
          too_many = Array.new(limit + 1) { { type: 'custom', value: 'package governance' } }

          post api(path, current_user), params: policy_params.merge(rules: too_many).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include("rules exceeds maximum of #{limit} entries")
        end

        it 'accepts exactly the limit' do
          at_limit = Array.new(limit) { |index| { type: 'custom', value: "package governance\n\n# #{index}\n" } }

          post api(path, current_user), params: policy_params.merge(rules: at_limit).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['rules'].size).to eq(limit)
        end
      end

      context 'when a rule entry is larger than the store accepts' do
        let(:size_limit) { ::Gitlab::PolicyStore::Ports::PolicyRepository::ENTRY_SIZE_LIMIT }

        it 'returns 400 naming the position of the oversized entry' do
          oversized = [{ type: 'custom', value: 'p' * size_limit }]

          post api(path, current_user), params: policy_params.merge(rules: oversized).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('rules has an entry exceeding maximum size')
        end
      end

      context 'when actions carries more entries than the store accepts' do
        it 'returns 400, since actions is bounded the same way as rules' do
          limit = ::Gitlab::PolicyStore::Ports::PolicyRepository::ENTRY_COUNT_LIMITS[:actions]
          too_many = Array.new(limit + 1) { { type: 'block' } }

          post api(path, current_user), params: policy_params.merge(actions: too_many).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include("actions exceeds maximum of #{limit} entries")
        end
      end

      context 'when a rule carries a Hash value rather than Rego source' do
        let(:policy_params) do
          super().merge(rules: [{ type: 'environment', value: { names: %w[production] } }])
        end

        it 'stores the hash, since only a custom rule carries a string' do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['rules'])
            .to match([a_hash_including('type' => 'environment', 'value' => { 'names' => ['production'] })])
        end
      end

      context 'when a policy carries more than one rule' do
        let(:policy_params) do
          super().merge(rules: [
            { type: 'environment', value: { tiers: %w[production] } },
            { type: 'custom', value: "package governance\n\nviolation contains {\"msg\": \"no\"}\n" }
          ])
        end

        it 'exposes policy_rego as one package governance module carrying both rules', :aggregate_failures do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['policy_rego'].scan('package governance').length).to eq(1)
          expect(json_response['policy_rego']).to include('# rule 0: environment')
          expect(json_response['policy_rego']).to include('violation contains {"msg": "no"}')
        end
      end

      context 'when an action carries a configuration hash' do
        let(:policy_params) do
          super().merge(actions: [{ type: 'require_approval', value: { approvals_required: 2 } }])
        end

        it 'stores the hash, since an action value is only ever a hash' do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['actions']).to eq([{ 'type' => 'require_approval',
                                                    'value' => { 'approvals_required' => 2 } }])
        end
      end

      context 'when an action value is a string rather than a hash' do
        let(:policy_params) { super().merge(actions: [{ type: 'block', value: 'not-a-hash' }]) }

        it 'returns 400' do
          post api(path, current_user), params: policy_params.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('value')
        end
      end

      context 'when actions is null or empty in a JSON body' do
        [nil, []].each do |value|
          it "creates the policy with no actions for #{value.inspect}" do
            post api(path, current_user), params: policy_params.merge(actions: value).to_json,
              headers: { 'Content-Type' => 'application/json' }

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['actions']).to eq([])
          end
        end
      end

      context 'when a rule type is not one the catalogue offers' do
        let(:policy_params) { super().merge(rules: [{ type: 'not_a_rule', value: 'package governance' }]) }

        it 'returns 400 without reaching the store' do
          expect(Gitlab::PolicyStore).not_to receive(:create)

          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('does not have a valid value')
        end
      end

      context 'when an action type is not one the catalogue offers' do
        let(:policy_params) { super().merge(actions: [{ type: 'not_an_action' }]) }

        it 'returns 400 without reaching the store' do
          expect(Gitlab::PolicyStore).not_to receive(:create)

          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('does not have a valid value')
        end
      end

      context 'when both a policy scope and Rego are given' do
        let(:policy_params) do
          super().merge(
            policy_scope: { compliance_frameworks: [{ id: 5 }] },
            scope_rego: "package gitlab.scope\n\napplies := true\n"
          )
        end

        it 'returns 400 with the service message, so the two cannot disagree' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Only one of policy_scope or scope_rego can be provided')
        end
      end

      # Stubbed far below the real figure so the payloads stay small. The gem's shared
      # examples cover the boundary itself.
      context 'when the rules compile past the store size limit' do
        let(:limit) { 100 }

        before do
          stub_const("#{Gitlab::PolicyStore::Ports::PolicyRepository}::MAX_COMPILED_RULES_BYTES", limit)
        end

        # Two entries, so the reported figure is the merged module rather than either rule
        # or the sum of both: 60 + (60 - 19) for the declaration the merger drops.
        it 'returns 400 naming the merged size, so the store refusal reaches the caller' do
          expect do
            post api(path, current_user), params: policy_params.merge(rules: rules_merging_to(60) * 2).to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include("rules compile to 101 bytes, over the maximum of #{limit} bytes")
        end

        it 'accepts rules whose merged program is exactly at the maximum' do
          post api(path, current_user), params: policy_params.merge(rules: rules_merging_to(limit)).to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['policy_rego'].bytesize).to eq(limit)
        end
      end

      context 'when a policy scope compiles past the store size limit' do
        let(:limit) { Gitlab::PolicyStore::Ports::PolicyRepository::TEXT_LIMITS[:scope_rego] }

        let(:policy_params) do
          projects = Array.new(limit) { |index| { id: index + 1 } }

          super().merge(policy_scope: { projects: { including: projects } })
        end

        # A JSON body rather than the form encoding the sibling examples use, because this
        # many ids exceeds what Rack will parse from a query string.
        it 'returns 400, since the limit is checked after the scope is compiled' do
          expect do
            post api(path, current_user), params: policy_params.to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include("scope_rego exceeds maximum length of #{limit}")
        end
      end

      it_behaves_like 'an organization-scoped policy store endpoint' do
        let(:expected_success_status) { :created }
      end

      it_behaves_like 'authorizing granular token permissions', :create_govern_policy,
        expected_success_status: :created do
        let(:user) { owner }
        let(:boundary_object) { :instance }
        let(:request) { post api(path, personal_access_token: pat), params: policy_params }
      end
    end

    describe 'PATCH /organizations/:id/security/policy_store/:policy_id' do
      let(:target_policy) { policy }
      let(:path) { "/organizations/#{target_organization_id}/security/policy_store/#{target_policy.id}" }
      let(:policy_params) { { name: 'Renamed policy' } }

      subject(:perform_request) { patch api(path, current_user), params: policy_params }

      it 'applies the change and returns the policy' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          'id' => policy.id,
          'name' => 'Renamed policy',
          'version' => 2
        )
      end

      it 'persists the change' do
        perform_request

        get api(path, current_user)

        expect(json_response['name']).to eq('Renamed policy')
      end

      it 'accepts a JSON body as well as a form-encoded one' do
        patch api(path, current_user), params: { name: 'JSON rename' }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['name']).to eq('JSON rename')
      end

      context 'when a replacement rule does not parse' do
        let(:broken_rule) { { type: 'custom', value: "package governance\n\nviolation contains {\"msg\": \"x\" if {" } }

        it 'returns 400 naming the rule and the location, and leaves the policy unchanged' do
          expect do
            patch api(path, current_user), params: { rules: [broken_rule] }.to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.find(policy.id).to_h }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to match(/\Arules\[0\] is invalid: .+ \(at 3:\d+\)\z/)
        end
      end

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        ::Security::SecurityOrchestrationPolicies::PolicyStore::UpdateService

      it_behaves_like 'a policy store endpoint that maps an engine fault to 500' do
        let(:policy_params) { { rules: [{ type: 'custom', value: 'package governance' }] } }
        let(:tracked_context) { { organization_id: organization.id, policy_id: policy.id } }
      end

      context 'when the mode and lifecycle state change' do
        let(:policy_params) { { mode: 'audit', lifecycle_state: 'disabled' } }

        it 'takes the policy off the store defaults' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('mode' => 'audit', 'lifecycle_state' => 'disabled')
        end
      end

      context 'when the actions change' do
        let!(:target_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Blocking policy',
            trigger_type: 'deployment_requested',
            actions: [{ 'type' => 'block' }]
          )
        end

        it 'replaces them rather than merging into the stored ones' do
          patch api(path, current_user),
            params: { actions: [{ type: 'require_approval', value: { approvals_required: 2 } }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['actions'])
            .to eq([{ 'type' => 'require_approval', 'value' => { 'approvals_required' => 2 } }])
        end
      end

      context 'when no changeable attribute is given' do
        let(:policy_params) { {} }

        it 'returns 400 rather than bumping the version for nothing' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when a blank scope_rego retires an authored program' do
        let!(:target_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Authored scope',
            trigger_type: 'deployment_requested',
            scope_rego: "package gitlab.scope\n\n# hand written"
          )
        end

        it 'recompiles when the blank arrives form-encoded as an empty string', :aggregate_failures do
          patch api(path, current_user), params: { scope_rego: '' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['scope_rego']).not_to include('# hand written')
          expect(json_response['scope_rego']).to include('applies to all projects')
          expect(json_response['scope_dimensions']).to eq([])
        end

        it 'recompiles when the blank arrives as JSON null' do
          patch api(path, current_user), params: { scope_rego: nil }.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['scope_rego']).not_to include('# hand written')
          expect(json_response['scope_rego']).to include('applies to all projects')
        end
      end

      context 'when the rules are emptied' do
        let!(:target_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Ruled policy',
            trigger_type: 'deployment_requested',
            rules: [{ 'type' => 'custom', 'value' => 'package governance' }]
          )
        end

        it 'stores the empty array, which is what a policy created without rules holds', :aggregate_failures do
          patch api(path, current_user), params: { rules: [] }.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['rules']).to eq([])
          expect(json_response['policy_rego']).to be_nil
        end
      end

      # Runs against the backend production configures, so the refusal is read back out of
      # Postgres rather than out of an in-memory copy of the same objects.
      context 'when the replacement rules compile past the store size limit' do
        include_context 'with a persistent policy store'

        let(:limit) { 100 }

        let!(:target_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Sized policy',
            trigger_type: 'deployment_requested',
            rules: [{ 'type' => 'custom', 'value' => 'package governance' }]
          )
        end

        before do
          stub_const("#{Gitlab::PolicyStore::Ports::PolicyRepository}::MAX_COMPILED_RULES_BYTES", limit)
        end

        it 'returns 400 and leaves the stored policy untouched', :aggregate_failures do
          expect do
            patch api(path, current_user), params: { rules: rules_merging_to(limit + 1) }.to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.to not_change { Gitlab::PolicyStore.find(target_policy.id).rules }
            .and not_change { Gitlab::PolicyStore.find(target_policy.id).version }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include("over the maximum of #{limit} bytes")
        end
      end

      context 'when a rules element is blank' do
        it 'returns 400 and names the position' do
          expect { patch api(path, current_user), params: { rules: [''] } }
            .not_to change { Gitlab::PolicyStore.find(policy.id).rules }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules[0] is blank')
        end

        it 'returns 400 for an empty object in a JSON body' do
          expect do
            patch api(path, current_user), params: { rules: [{}] }.to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.find(policy.id).rules }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('rules[0] is blank')
        end
      end

      context 'when an actions element is blank' do
        it 'returns 400 rather than storing the blank element' do
          expect { patch api(path, current_user), params: { actions: [''] } }
            .not_to change { Gitlab::PolicyStore.find(policy.id).actions }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include('actions[0] is blank')
        end
      end

      context 'when an update pushes rules past the entry count' do
        let(:limit) { ::Gitlab::PolicyStore::Ports::PolicyRepository::ENTRY_COUNT_LIMITS[:rules] }

        it 'returns 400 rather than storing the oversized array' do
          too_many = Array.new(limit + 1) { { type: 'custom', value: 'package governance' } }

          expect do
            patch api(path, current_user), params: { rules: too_many }.to_json,
              headers: { 'Content-Type' => 'application/json' }
          end.not_to change { Gitlab::PolicyStore.find(policy.id).rules }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include("rules exceeds maximum of #{limit} entries")
        end
      end

      context 'when an update carries a rule entry larger than the store accepts' do
        it 'returns 400 from the store' do
          size_limit = ::Gitlab::PolicyStore::Ports::PolicyRepository::ENTRY_SIZE_LIMIT
          oversized = [{ type: 'custom', value: 'p' * size_limit }]

          patch api(path, current_user), params: { rules: oversized }.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('rules has an entry exceeding maximum size')
        end
      end

      context 'when an empty policy scope un-scopes the policy' do
        let!(:target_policy) do
          create_policy(
            organization_id: organization.id,
            name: 'Scoped policy',
            trigger_type: 'deployment_requested',
            policy_scope: { 'compliance_frameworks' => [{ 'id' => 5 }] }
          )
        end

        it 'clears the scope, which only a JSON body can express', :aggregate_failures do
          patch api(path, current_user), params: { policy_scope: {} }.to_json,
            headers: { 'Content-Type' => 'application/json' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['scope_rego']).to include('applies to all projects')
          expect(json_response['scope_rego']).not_to include('framework_id')
          expect(json_response['scope_dimensions']).to eq([])
        end
      end

      context 'when the policy does not exist' do
        let(:path) do
          "/organizations/#{target_organization_id}/security/policy_store/#{non_existing_record_id}"
        end

        it 'returns 404 naming the policy' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      context 'when the policy belongs to another organization' do
        let!(:target_policy) do
          create_policy(
            organization_id: other_organization.id,
            name: 'Other organization policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'returns the same 404 as a missing policy and leaves it unchanged' do
          expect { perform_request }
            .not_to change { Gitlab::PolicyStore.find(target_policy.id).name }

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      {
        { trigger_type: 'not_a_trigger' } => 'trigger_type',
        { mode: 'not_a_mode' } => 'mode',
        { lifecycle_state: 'not_a_lifecycle_state' } => 'lifecycle_state',
        { rules: [{ type: 'not_a_rule' }] } => 'rules[0][type]',
        { actions: [{ type: 'not_an_action' }] } => 'actions[0][type]'
      }.each do |invalid_params, rejected_parameter|
        context "when #{rejected_parameter} is not one the catalogue offers" do
          it 'returns 400, since the route is the only thing that constrains it' do
            patch api(path, current_user), params: invalid_params.to_json,
              headers: { 'Content-Type' => 'application/json' }

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['error']).to eq("#{rejected_parameter} does not have a valid value")
          end
        end
      end

      context 'when a free-form string is longer than the store accepts' do
        ::Gitlab::PolicyStore::Ports::PolicyRepository::TEXT_LIMITS.each do |attribute, limit|
          it "returns 400 for #{attribute}, so the payload is refused before the store parses it" do
            patch api(path, current_user), params: { attribute => 'a' * (limit + 1) }.to_json,
              headers: { 'Content-Type' => 'application/json' }

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['error']).to include(attribute.to_s, "must be less than #{limit} characters")
          end

          it "accepts #{attribute} at exactly #{limit} characters" do
            patch api(path, current_user), params: { attribute => at_limit_value(attribute, limit) }.to_json,
              headers: { 'Content-Type' => 'application/json' }

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when both a policy scope and Rego are given' do
        let(:policy_params) do
          {
            policy_scope: { compliance_frameworks: [{ id: 5 }] },
            scope_rego: "package gitlab.scope\n\napplies := true\n"
          }
        end

        it 'returns 400 with the service message' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Only one of policy_scope or scope_rego can be provided')
        end
      end

      context 'when the new name is taken by another policy in the organization' do
        before do
          create_policy(
            organization_id: organization.id,
            name: 'Renamed policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'returns 400 with the store message' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Name has already been taken')
        end
      end

      it_behaves_like 'an organization-scoped policy store endpoint'

      it_behaves_like 'authorizing granular token permissions', :update_govern_policy do
        let(:user) { owner }
        let(:boundary_object) { :instance }
        let(:request) { patch api(path, personal_access_token: pat), params: policy_params }
      end
    end

    describe 'DELETE /organizations/:id/security/policy_store/:policy_id' do
      let(:target_policy_id) { policy.id }
      let(:path) { "/organizations/#{target_organization_id}/security/policy_store/#{target_policy_id}" }

      subject(:perform_request) { delete api(path, current_user) }

      it 'deletes the policy and returns no content' do
        expect { perform_request }
          .to change { Gitlab::PolicyStore.list(organization_id: organization.id).size }.by(-1)

        expect(response).to have_gitlab_http_status(:no_content)
        expect(response.body).to be_empty
      end

      context 'when the policy does not exist' do
        let(:target_policy_id) { non_existing_record_id }

        it 'returns 404 naming the policy' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      # let! rather than let: the policy has to exist before the change matcher takes its
      # baseline, otherwise creating it inside the block reads as the delete having failed.
      context 'when the policy belongs to another organization' do
        let!(:target_policy_id) do
          create_policy(
            organization_id: other_organization.id,
            name: 'Other organization policy',
            trigger_type: 'deployment_requested'
          ).id
        end

        it 'returns the same 404 as a missing policy and leaves it in the store' do
          expect { perform_request }
            .not_to change { Gitlab::PolicyStore.list(organization_id: other_organization.id).size }

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      it_behaves_like 'an organization-scoped policy store endpoint' do
        let(:expected_success_status) { :no_content }
      end

      it_behaves_like 'authorizing granular token permissions', :delete_govern_policy,
        expected_success_status: :no_content do
        let(:user) { owner }
        let(:boundary_object) { :instance }
        let(:request) { delete api(path, personal_access_token: pat) }
      end
    end
  end

  describe 'the group-scoped routes', :policy_store do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:other_group) { create(:group, organization: organization) }
    let_it_be(:private_group) { create(:group, :private, organization: organization) }
    let_it_be(:owner) { create(:user, organization: organization) }
    let_it_be(:member) { create(:user, organization: organization) }

    let(:current_user) { owner }
    let(:target_group) { group }
    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Block deployments on critical findings',
        trigger_type: 'deployment_requested'
      )
    end

    subject(:perform_request) { get api(path, current_user) }

    before_all do
      group.add_owner(owner)
      group.add_developer(member)
      other_group.add_owner(owner)
      private_group.add_owner(owner)
    end

    before do
      ::Organizations::OrganizationSetting.for(organization.id).update!(policy_store_experiment_enabled: true)
      [group, other_group, private_group].each do |g|
        NamespaceSetting.find_or_initialize_by(namespace_id: g.id).update!(policy_store_experiment_enabled: true)
      end
    end

    shared_examples 'a group-scoped policy store endpoint' do
      let(:expected_success_status) { :ok }

      context 'when the user is a group member without the owner role' do
        let(:current_user) { member }

        it 'returns 403' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when the user does not belong to the group' do
        let(:current_user) { create(:user) }

        it 'returns 403, since the group is public but the user lacks permission' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when the group is private and the user does not belong to it' do
        let(:current_user) { create(:user) }
        let(:target_group) { private_group }

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the group does not exist' do
        let(:target_group) { instance_double(Group, to_param: non_existing_record_id) }

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when unauthenticated' do
        let(:current_user) { nil }

        it 'returns 401' do
          perform_request

          expect(response).to have_gitlab_http_status(:unauthorized)
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(security_policies_v2: false)
        end

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the experiment is disabled for the instance' do
        before do
          stub_application_setting(policy_store_experiment_enabled: false)
        end

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the experiment is disabled for the group' do
        before do
          NamespaceSetting.find_or_initialize_by(namespace_id: group.id).update!(policy_store_experiment_enabled: false)
        end

        it 'returns 403' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when the license is not available' do
        before do
          stub_licensed_features(security_orchestration_policies: false)
        end

        it 'returns 403' do
          perform_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end

    describe 'GET /groups/:id/security/policy_store' do
      let(:path) { "/groups/#{target_group.to_param}/security/policy_store" }

      it 'returns the policies of the group' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to contain_exactly(
          a_hash_including(
            'id' => policy.id,
            'organization_id' => organization.id,
            'namespace_id' => group.id,
            'name' => 'Block deployments on critical findings',
            'trigger_type' => 'deployment_requested'
          )
        )
      end

      it 'matches the policies schema' do
        perform_request

        expect(response).to match_response_schema('public_api/v4/govern_policies', dir: 'ee')
      end

      context 'when there are policies in another group' do
        before do
          create_policy(
            organization_id: organization.id,
            namespace_id: other_group.id,
            name: 'Other group policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'returns only the policies belonging to the requested group' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.size).to eq(1)
          expect(json_response.first['namespace_id']).to eq(group.id)
        end
      end

      context 'when there are organization-wide policies' do
        before do
          create_policy(
            organization_id: organization.id,
            namespace_id: nil,
            name: 'Organization-wide policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'does not return organization-wide policies' do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.size).to eq(1)
          expect(json_response.first['namespace_id']).to eq(group.id)
        end
      end

      context 'with the persistent repository', :aggregate_failures do
        include_context 'with a persistent policy store'

        it 'does not grow with the number of policies on the page' do
          control = ActiveRecord::QueryRecorder.new(skip_cached: false) { get api(path, current_user) }

          create_policy(
            organization_id: organization.id,
            namespace_id: group.id,
            name: 'Another policy',
            trigger_type: 'deployment_requested'
          )

          expect { get api(path, current_user) }.not_to exceed_all_query_limit(control)
        end
      end

      it_behaves_like 'a group-scoped policy store endpoint'

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        Security::SecurityOrchestrationPolicies::PolicyStore::ListService

      it_behaves_like 'authorizing granular token permissions', :read_govern_policy do
        let(:user) { owner }
        let(:boundary_object) { group }
        let(:request) { get api(path, personal_access_token: pat) }
      end
    end

    describe 'GET /groups/:id/security/policy_store/:policy_id' do
      let(:target_policy_id) { policy.id }
      let(:path) { "/groups/#{target_group.to_param}/security/policy_store/#{target_policy_id}" }

      it 'returns the policy' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          'id' => policy.id,
          'organization_id' => organization.id,
          'namespace_id' => group.id,
          'name' => 'Block deployments on critical findings'
        )
      end

      context 'when the policy does not exist' do
        let(:target_policy_id) { non_existing_record_id }

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      context 'when the policy belongs to another group' do
        let(:other_group_policy) do
          create_policy(
            organization_id: organization.id,
            namespace_id: other_group.id,
            name: 'Other group policy',
            trigger_type: 'deployment_requested'
          )
        end

        let(:target_policy_id) { other_group_policy.id }

        it 'returns 404, same as a missing policy' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      context 'when the policy is organization-wide' do
        let(:org_policy) do
          create_policy(
            organization_id: organization.id,
            namespace_id: nil,
            name: 'Organization-wide policy',
            trigger_type: 'deployment_requested'
          )
        end

        let(:target_policy_id) { org_policy.id }

        it 'returns 404, since a group cannot see organization-wide policies' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      it_behaves_like 'a group-scoped policy store endpoint'

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        Security::SecurityOrchestrationPolicies::PolicyStore::FindService

      it_behaves_like 'authorizing granular token permissions', :read_govern_policy do
        let(:user) { owner }
        let(:boundary_object) { group }
        let(:request) { get api(path, personal_access_token: pat) }
      end
    end

    describe 'POST /groups/:id/security/policy_store' do
      let(:path) { "/groups/#{target_group.to_param}/security/policy_store" }
      let(:policy_params) do
        {
          name: 'New group policy',
          trigger_type: 'deployment_requested',
          rules: [{ type: 'custom', value: 'package governance' }]
        }
      end

      subject(:perform_request) { post api(path, current_user), params: policy_params }

      it 'creates a policy scoped to the group' do
        expect { perform_request }.to change {
          Gitlab::PolicyStore.list(organization_id: organization.id, namespace_id: group.id).size
        }.by(1)

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response).to include(
          'organization_id' => organization.id,
          'namespace_id' => group.id,
          'name' => 'New group policy',
          'trigger_type' => 'deployment_requested'
        )
      end

      context 'when a policy with the same name exists in another group' do
        before do
          create_policy(
            organization_id: organization.id,
            namespace_id: other_group.id,
            name: 'New group policy',
            trigger_type: 'deployment_requested'
          )
        end

        it 'rejects the policy because names are unique per organization' do
          # NOTE: This test documents current behavior.
          # See https://gitlab.com/gitlab-org/gitlab/-/issues/628084 to scope
          # name uniqueness to the namespace level.
          expect { perform_request }.not_to change {
            Gitlab::PolicyStore.list(organization_id: organization.id, namespace_id: group.id).size
          }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Name has already been taken')
        end
      end

      context 'when the name is missing' do
        let(:policy_params) { { trigger_type: 'deployment_requested', rules: [{ type: 'custom' }] } }

        it 'returns 400' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      it_behaves_like 'a group-scoped policy store endpoint' do
        let(:expected_success_status) { :created }
      end

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        Security::SecurityOrchestrationPolicies::PolicyStore::CreateService

      it_behaves_like 'authorizing granular token permissions', :create_govern_policy,
        expected_success_status: :created do
        let(:user) { owner }
        let(:boundary_object) { group }
        let(:request) { post api(path, personal_access_token: pat), params: policy_params }
      end
    end

    describe 'PATCH /groups/:id/security/policy_store/:policy_id' do
      let(:target_policy_id) { policy.id }
      let(:path) { "/groups/#{target_group.to_param}/security/policy_store/#{target_policy_id}" }
      let(:policy_params) { { name: 'Renamed policy' } }

      subject(:perform_request) { patch api(path, current_user), params: policy_params }

      it 'updates the policy' do
        perform_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['name']).to eq('Renamed policy')
        expect(json_response['version']).to eq(2)
      end

      context 'when the policy does not exist' do
        let(:target_policy_id) { non_existing_record_id }

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      context 'when the policy belongs to another group' do
        let(:other_group_policy) do
          create_policy(
            organization_id: organization.id,
            namespace_id: other_group.id,
            name: 'Other group policy',
            trigger_type: 'deployment_requested'
          )
        end

        let(:target_policy_id) { other_group_policy.id }

        it 'returns 404 and does not update the policy' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(Gitlab::PolicyStore.find(other_group_policy.id).name).to eq('Other group policy')
        end
      end

      context 'when no changes are provided' do
        let(:policy_params) { {} }

        it 'returns 400' do
          perform_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      it_behaves_like 'a group-scoped policy store endpoint'

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        Security::SecurityOrchestrationPolicies::PolicyStore::UpdateService

      it_behaves_like 'authorizing granular token permissions', :update_govern_policy do
        let(:user) { owner }
        let(:boundary_object) { group }
        let(:request) { patch api(path, personal_access_token: pat), params: policy_params }
      end
    end

    describe 'DELETE /groups/:id/security/policy_store/:policy_id' do
      let(:target_policy_id) { policy.id }
      let(:path) { "/groups/#{target_group.to_param}/security/policy_store/#{target_policy_id}" }

      subject(:perform_request) { delete api(path, current_user) }

      it 'deletes the policy and returns no content' do
        expect { perform_request }.to change {
          Gitlab::PolicyStore.list(organization_id: organization.id, namespace_id: group.id).size
        }.by(-1)

        expect(response).to have_gitlab_http_status(:no_content)
        expect(response.body).to be_empty
      end

      context 'when the policy does not exist' do
        let(:target_policy_id) { non_existing_record_id }

        it 'returns 404' do
          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('404 Policy Not Found')
        end
      end

      context 'when the policy belongs to another group' do
        let!(:other_group_policy) do
          create_policy(
            organization_id: organization.id,
            namespace_id: other_group.id,
            name: 'Other group policy',
            trigger_type: 'deployment_requested'
          )
        end

        let(:target_policy_id) { other_group_policy.id }

        it 'returns 404 and does not delete the policy' do
          expect { perform_request }.not_to change {
            Gitlab::PolicyStore.list(organization_id: organization.id, namespace_id: other_group.id).size
          }

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      it_behaves_like 'a group-scoped policy store endpoint' do
        let(:expected_success_status) { :no_content }
      end

      it_behaves_like 'a policy store endpoint that maps forbidden to 403',
        Security::SecurityOrchestrationPolicies::PolicyStore::DestroyService

      it_behaves_like 'authorizing granular token permissions', :delete_govern_policy,
        expected_success_status: :no_content do
        let(:user) { owner }
        let(:boundary_object) { group }
        let(:request) { delete api(path, personal_access_token: pat) }
      end
    end
  end
end
