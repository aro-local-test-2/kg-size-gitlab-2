# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ai::DuoWorkflows::Workflows, :with_current_organization, feature_category: :duo_agent_platform do
  include HttpBasicAuthHelpers

  let_it_be_with_refind(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :repository, group: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }
  let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:duo_workflow_service_url) { 'duo-workflow-service.example.com:50052' }
  let_it_be(:ai_workflows_oauth_token) do
    create(:oauth_access_token, user: user, scopes: [:ai_workflows])
  end

  let_it_be(:auth_response) { Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [group.id]) }
  let(:agent_privileges) { [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES] }
  let(:pre_approved_agent_privileges) { [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES] }
  let(:workflow_definition) { 'software_development' }
  let(:allow_agent_to_request_user) { false }
  let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

  before_all do
    group.add_developer(user)
    project.add_member(service_account, Gitlab::Access::DEVELOPER)
  end

  before do
    # `duo_workflow_direct_access` allows 50 requests a minute keyed on the user, and three
    # endpoints in this file share that bucket with the same `user`, so a full run trips it
    # depending on example order. The examples that assert throttling stub it back on.
    allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_return(false)

    # The precondition check runs on by default; make the factory project look runner-ready.
    stub_duo_runner_available(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :duo_workflow).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :foundational_flows).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :foundational_flows).and_return(true)

    allow_any_instance_of(User).to receive(:allowed_to_use).and_return(auth_response) # rubocop:disable RSpec/AnyInstanceOf -- not the next instance
    allow_next_instance_of(::Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService) do |service|
      allow(service).to receive(:execute).and_return(
        ServiceResponse.success(
          payload: {
            oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'token-12345')
          }
        )
      )
    end

    ::Ai::Setting.for_organization(project.organization).update!(
      duo_workflow_service_account_user_id: service_account.id
    )
    allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor).and_call_original
    allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor)
      .with(user).and_return(service_account)
    allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor)
      .with(service_account).and_return(service_account)
    project.update!(allow_composite_identities_to_run_pipelines: true)
    project.reload
  end

  shared_context 'with user governing namespace' do
    before do
      # rubocop:disable RSpec/AnyInstanceOf -- user is reloaded during request
      allow_any_instance_of(User).to receive(:governing_namespace).and_return(governing_namespace)
      # rubocop:enable RSpec/AnyInstanceOf
    end
  end

  shared_context 'when identity verification blocks the user' do
    before do
      allow_next_found_instance_of(User) do |found_user|
        allow(found_user).to receive(:dap_identity_verification_required?).and_return(true)
      end
    end
  end

  describe 'POST /ai/duo_workflows/workflows' do
    let(:path) { "/ai/duo_workflows/workflows" }
    let(:container) { { project_id: project.id } }
    let(:params) do
      {
        agent_privileges: agent_privileges,
        pre_approved_agent_privileges: pre_approved_agent_privileges,
        workflow_definition: workflow_definition,
        allow_agent_to_request_user: allow_agent_to_request_user,
        image: "example.com/example-image:latest",
        environment: "web",
        ai_catalog_item_consumer_id: nil
      }.merge(container)
    end

    before do
      allow_next_instance_of(Ai::UsageQuotaService) do |instance|
        allow(instance).to receive(:execute).and_return(
          ServiceResponse.success
        )
      end
    end

    # Nobody asked Rails to execute the flow, so the client executes it with the
    # user's own token. The governance matrix is covered in
    # ee/spec/services/ai/duo_workflows/flow_execution_authorizer_spec.rb; these
    # examples cover the seams: params wiring, and that the container does not
    # change the outcome.
    shared_examples 'a client-executed flow create' do
      it 'creates a session that runs as the user, not a service account' do
        expect do
          post api(path, user), params: params
        end.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        expect(response).to have_gitlab_http_status(:created)

        created_workflow = Ai::DuoWorkflows::Workflow.last
        expect(created_workflow.workflow_definition).to eq('developer/v1')
        expect(created_workflow.service_account_id).to be_nil
        expect(created_workflow.environment).to eq('ide')
      end

      it 'does not consult the per-container flow allowlist' do
        expect(Ability).not_to receive(:allowed?).with(user, :execute_ai_catalog_item, anything)

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
      end

      context 'when the caller asks GitLab to execute the flow' do
        let(:params) { super().merge(start_workflow: true) }

        it 'stays catalog-governed and is forbidden without an item consumer' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end

    context 'when a foundational flow is client-executed' do
      let_it_be(:developer_catalog_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')
      end

      let(:workflow_definition) { 'developer/v1' }
      let(:params) { super().merge(environment: 'ide') }

      before do
        allow(::Ai::Catalog::FoundationalFlow.developer_v1).to receive(:catalog_item)
          .and_return(developer_catalog_item)
      end

      context 'when the run is outside a project' do
        let(:container) { { namespace_id: group.id } }

        context 'with agentic chat access stubbed' do
          before do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, group).and_return(true)
          end

          it_behaves_like 'a client-executed flow create'

          it 'scopes the session to the namespace' do
            post api(path, user), params: params

            created_workflow = Ai::DuoWorkflows::Workflow.last
            expect(created_workflow.namespace).to eq(group)
            expect(created_workflow.project).to be_nil
          end

          # See Ai::DuoWorkflows::FlowExecutionAuthorizer::WAIVED_ITEM_CONSUMER_CONDITIONS.
          it 'creates the session when the owner disabled foundational flows' do
            group.namespace_settings.update!(duo_foundational_flows_enabled: false)

            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end
        end

        # Exercises the real GroupPolicy rather than stubbing it, so a policy regression
        # cannot pass unnoticed.
        context 'with the real agentic chat policy' do
          before do
            stub_licensed_features(ai_features: true, agentic_chat: true, ai_workflows: true)
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
            allow(::Gitlab::Llm::StageCheck).to receive(:available?)
              .with(group, :agentic_chat).and_return(true)
            allow(::Gitlab::Llm::StageCheck).to receive(:available?)
              .with(group, :duo_workflow).and_return(true)
          end

          it 'creates the session' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end

          # The configurable minimum role for execution, not the asynchronous one.
          it 'is forbidden when the minimum role for execution excludes the user' do
            ::Ai::Setting.for_organization(group.organization)
              .update!(minimum_access_level_execute: ::Gitlab::Access::MAINTAINER)

            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end
      end

      context 'when the run is inside a project' do
        # No :repository trait - this context never touches git, and seeding another
        # Gitaly repository from a let_it_be leaks state into later spec files.
        let_it_be_with_reload(:unlisted_project) { create(:project, group: group, developers: user) }

        let(:container) { { project_id: unlisted_project.id } }

        before do
          unlisted_project.update!(duo_features_enabled: true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
          allow(::Gitlab::Llm::StageCheck).to receive(:available?)
            .with(unlisted_project, :duo_workflow).and_return(true)
        end

        context 'with agentic chat access stubbed' do
          before do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?)
              .with(user, :access_duo_agentic_chat, unlisted_project).and_return(true)
          end

          it_behaves_like 'a client-executed flow create'

          it 'scopes the session to the project' do
            post api(path, user), params: params

            expect(Ai::DuoWorkflows::Workflow.last.project).to eq(unlisted_project)
          end

          it 'sends the user, not a service account, as the AI Gateway subject' do
            expect(Gitlab::AiGateway).to receive(:public_headers)
              .with(hash_including(subject: user)).and_return({})

            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end

          # :create_duo_workflow_for_ci carries the minimum role for asynchronous execution,
          # which must not reach a run the caller performs itself.
          context 'when the minimum role for asynchronous execution excludes the user' do
            before do
              ::Ai::Setting.for_organization(unlisted_project.organization)
                .update!(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)
            end

            it 'creates the session, because the run is not asynchronous execution' do
              expect(Ability).not_to receive(:allowed?)
                .with(user, :create_duo_workflow_for_ci, unlisted_project)

              post api(path, user), params: params

              expect(response).to have_gitlab_http_status(:created)
            end
          end
        end

        # Exercises the real agentic chat policy rather than stubbing it, so a policy
        # regression cannot pass unnoticed.
        context 'with the real agentic chat policy' do
          before do
            stub_licensed_features(ai_features: true, agentic_chat: true, ai_workflows: true)
            allow(::Gitlab::Llm::StageCheck).to receive(:available?)
              .with(unlisted_project, :agentic_chat).and_return(true)
          end

          it 'creates the session' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end
        end

        # Regression: a valid Duo seat held in another namespace, used in a project
        # whose namespace has no seat. A client-executed flow must allow it, as chat did.
        # https://gitlab.com/gitlab-org/gitlab/-/issues/623975
        context 'when the Duo seat is in another namespace' do
          before do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?)
              .with(user, :access_duo_agentic_chat, unlisted_project).and_return(true)
            allow(Ability).to receive(:allowed?)
              .with(user, :duo_workflow, unlisted_project).and_return(false)
          end

          it 'creates the session' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end
        end
      end
    end

    context 'when identity verification is required' do
      include_context 'when identity verification blocks the user'

      it 'refuses before reaching the service', :aggregate_failures do
        expect(::Ai::DuoWorkflows::CreateWorkflowService).not_to receive(:new)

        expect { post api(path, user), params: params }.not_to change { Ai::DuoWorkflows::Workflow.count }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when workflow is chat' do
      let_it_be(:default_organization) { create(:organization) }

      let(:workflow_definition) { 'chat' }

      before do
        allow(Gitlab::AiGateway).to receive(:public_headers)
          .with(hash_including(user: user, ai_feature_name: :duo_workflow,
            unit_primitive_name: :duo_workflow_execute_workflow))
          .and_return({ 'x-gitlab-enabled-feature-flags' => 'test-feature' })
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, project).and_return(true)

        allow(::Organizations::Organization).to receive(:default_organization).and_return(default_organization)
      end

      it 'creates the Ai::DuoWorkflows::Workflow' do
        expect do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:created)
        end.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        created_workflow = Ai::DuoWorkflows::Workflow.last

        expect(created_workflow.workflow_definition).to eq(workflow_definition)
      end

      context 'when user has no governing namespace' do
        include_context 'with user governing namespace' do
          let(:governing_namespace) { nil }
        end

        it 'creates the workflow successfully with nil governing_namespace_id' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end

        it 'does not push duo_agentic_chat_prefer_mcp_tools feature flag' do
          allow(Gitlab::AiGateway).to receive(:push_feature_flag).and_call_original

          post api(path, user), params: params

          expect(Gitlab::AiGateway).not_to have_received(:push_feature_flag)
            .with(:duo_agentic_chat_prefer_mcp_tools, anything)
        end
      end

      context 'when user has a governing namespace' do
        include_context 'with user governing namespace' do
          let(:governing_namespace) { group }
        end

        before do
          stub_feature_flags(duo_agentic_chat_prefer_mcp_tools: group)
          allow(Gitlab::AiGateway).to receive(:push_feature_flag).and_call_original
        end

        it 'pushes duo_agentic_chat_prefer_mcp_tools feature flag for the governing namespace' do
          post api(path, user), params: params

          expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
            .with(:duo_agentic_chat_prefer_mcp_tools, group)
        end
      end

      context 'with namespace-level workflow' do
        let(:container) { { namespace_id: group.id } }

        before do
          allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, group).and_return(true)
        end

        it 'creates a workflow' do
          post api(path, user), params: params

          created_workflow = Ai::DuoWorkflows::Workflow.last
          expect(json_response['id']).to eq(created_workflow.id)
          expect(json_response['namespace_id']).to eq(created_workflow.namespace.id)
          expect(json_response['namespace_id']).to eq(group.id)
          expect(json_response['project_id']).to be_nil
        end
      end

      context 'when neither project_id nor namespace_id are specified' do
        let(:container) { {} }

        context 'when user has a default duo namespace' do
          let(:default_namespace) { create(:group) }

          before do
            default_namespace.add_developer(user)
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(default_namespace,
              :agentic_chat).and_return(true)
            user.user_preference.update!(duo_default_namespace_id: default_namespace.id)
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat,
              default_namespace).and_return(true)
          end

          it 'creates a workflow using the default namespace' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
            created_workflow = Ai::DuoWorkflows::Workflow.last
            expect(json_response['id']).to eq(created_workflow.id)
            expect(json_response['namespace_id']).to eq(default_namespace.id)
            expect(json_response['project_id']).to be_nil
          end
        end

        context 'when user has no default duo namespace' do
          before do
            allow_any_instance_of(UserPreference).to receive(:duo_default_namespace_with_fallback).and_return(nil) # rubocop:disable RSpec/AnyInstanceOf -- user is reloaded during request
          end

          it 'returns error' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(response.body).to include('No default namespace found')
          end
        end

        context 'when user cannot access their default duo namespace' do
          let(:inaccessible_namespace) { create(:group, :private) }

          before do
            # User is NOT a member of this private namespace
            allow_any_instance_of(UserPreference).to receive(:duo_default_namespace_with_fallback).and_return(inaccessible_namespace) # rubocop:disable RSpec/AnyInstanceOf -- user is reloaded during request
          end

          it 'returns forbidden error' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:forbidden)
            expect(response.body).to include('Access to the container is not allowed')
          end
        end
      end

      context 'when both project_id and namespace_id are specified' do
        let(:container) { { project_id: project.id, namespace_id: group.id } }

        it 'uses project_id and ignores namespace_id' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)

          created_workflow = Ai::DuoWorkflows::Workflow.last
          expect(json_response['id']).to eq(created_workflow.id)
          expect(json_response['project_id']).to eq(created_workflow.project.id)
          expect(json_response['project_id']).to eq(project.id)
          expect(json_response['namespace_id']).to be_nil
        end
      end

      context 'when project_id does not exist' do
        let(:container) { { project_id: non_existing_record_id } }

        it 'returns not found error' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when namespace_id does not exist' do
        let(:container) { { namespace_id: non_existing_record_id } }

        it 'returns not found error' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when success' do
      before do
        allow(Gitlab::AiGateway).to receive(:public_headers)
          .with(hash_including(user: user, ai_feature_name: :duo_workflow,
            unit_primitive_name: :duo_workflow_execute_workflow))
          .and_return({ 'x-gitlab-enabled-feature-flags' => 'test-feature' })
      end

      it 'creates the Ai::DuoWorkflows::Workflow' do
        expect do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:created)
        end.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        expect(json_response['id']).to eq(Ai::DuoWorkflows::Workflow.last.id)
        expect(json_response['environment']).to eq("web")
        expect(response.headers['X-Gitlab-Enabled-Feature-Flags']).to include('test-feature')

        created_workflow = Ai::DuoWorkflows::Workflow.last

        expect(created_workflow.agent_privileges).to eq(agent_privileges)
        # READ_WRITE_FILES resolves to Ask on web, so it does not survive the clamp.
        expect(created_workflow.pre_approved_agent_privileges).to eq([])
        expect(created_workflow.workflow_definition).to eq(workflow_definition)
        expect(created_workflow.allow_agent_to_request_user).to eq(allow_agent_to_request_user)
        expect(created_workflow.image).to eq("example.com/example-image:latest")
        expect(created_workflow.environment).to eq("web")
      end

      it_behaves_like 'authorizing granular token permissions', :create_duo_workflow do
        let(:boundary_object) { :user }
        let(:request) { post api(path, personal_access_token: pat), params: params }
      end

      context 'with namespace-level workflow' do
        let(:container) { { namespace_id: group.id } }

        it 'creates a namespace-level workflow' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when agent_privileges is not provided' do
        let(:params) { { project_id: project.id } }

        it 'creates a workflow with the default agent_privileges' do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:created)

          created_workflow = Ai::DuoWorkflows::Workflow.last

          expect(created_workflow.agent_privileges).to match_array(
            ::Ai::DuoWorkflows::Workflow::AgentPrivileges::DEFAULT_PRIVILEGES +
            [::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS,
              ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES]
          )
        end
      end

      context 'when pre_approved_agent_privileges is not provided' do
        let(:params) do
          {
            project_id: project.id,
            agent_privileges: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::DEFAULT_PRIVILEGES
          }
        end

        it 'creates a workflow with the resolved pre_approved_agent_privileges' do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:created)

          created_workflow = Ai::DuoWorkflows::Workflow.last
          # Resolved pre-approvals are adopted, and only READ_ONLY_GITLAB is pre-approved by default.
          expect(created_workflow.pre_approved_agent_privileges).to match_array(
            [Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB]
          )
        end
      end

      context 'when pre_approved_agent_privileges has invalid privilege' do
        let(:params) do
          {
            project_id: project.id,
            agent_privileges: [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES],
            pre_approved_agent_privileges: [999]
          }
        end

        it 'returns bad request' do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when pre_approved_agent_privileges contains privilege not in agent_privileges' do
        let(:params) do
          {
            project_id: project.id,
            agent_privileges: [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES],
            pre_approved_agent_privileges: [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB]
          }
        end

        it 'returns bad request' do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when allow_agent_to_request_user is not provided' do
        it 'creates a workflow with the default of true' do
          post api(path, user), params: params.except(:allow_agent_to_request_user)
          expect(response).to have_gitlab_http_status(:created)

          created_workflow = Ai::DuoWorkflows::Workflow.last
          expect(created_workflow.allow_agent_to_request_user).to be(true)
        end
      end

      context 'when workflow definition is not provided' do
        let(:params) { { project_id: project.id } }

        it 'creates a workflow with the default workflow_definition' do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:created)

          created_workflow = Ai::DuoWorkflows::Workflow.last
          expect(created_workflow.workflow_definition).to eq('software_development')
        end
      end

      context 'when authenticated with a token that has the ai_workflows scope' do
        it 'is forbidden' do
          post api(path, oauth_access_token: ai_workflows_oauth_token), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'with project path params' do
        let(:params) { { project_id: project.full_path } }

        it 'is successful' do
          expect do
            post api(path, user), params: params
            expect(response).to have_gitlab_http_status(:created)
          end.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when environment is chat_partial' do
        let(:params) { { project_id: project.id, environment: 'chat_partial' } }

        it 'creates a workflow with chat_partial environment' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
          created_workflow = Ai::DuoWorkflows::Workflow.last
          expect(created_workflow.environment).to eq('chat_partial')
        end
      end

      context 'when source param is provided' do
        it 'keeps the client-surface values released clients send' do
          # Released Duo CLI / Language Server builds send these literals; removing one
          # returns 400 on every session create from those clients. See
          # https://gitlab.com/gitlab-org/gitlab/-/work_items/612068.
          expect(::Ai::DuoWorkflows::Workflow::CLIENT_SOURCE_TYPES.keys)
            .to include(:duo_cli_interactive, :duo_cli_run, :duo_cli_acp, :ide_extension)
        end

        context "with valid values" do
          it 'creates the workflow with the source persisted as source_type' do
            ::Ai::DuoWorkflows::Workflow::CLIENT_SOURCE_TYPES.keys.map(&:to_s).each do |action_source|
              request_params = params.merge(source: action_source)

              post api(path, user), params: request_params

              expect(response).to have_gitlab_http_status(:created)
              expect(Ai::DuoWorkflows::Workflow.find(json_response['id']).source_type).to eq(action_source)
            end
          end

          it 'tracks the session created event with source in additional_properties' do
            ::Ai::DuoWorkflows::Workflow::CLIENT_SOURCE_TYPES.keys.map(&:to_s).each do |action_source|
              request_params = params.merge(source: action_source)

              expect { post api(path, user), params: request_params }
                .to trigger_internal_events('agent_platform_session_created')
                      .with(
                        category: 'Ai::DuoWorkflows::CreateWorkflowService',
                        user: user,
                        project: project,
                        additional_properties: { source: action_source }
                      )
            end
          end
        end

        context 'with a server-only value' do
          it 'rejects it even though it is a valid source_type' do
            ::Ai::DuoWorkflows::Workflow::SERVER_SOURCE_TYPES.keys.map(&:to_s).each do |server_source|
              post api(path, user), params: params.merge(source: server_source)

              expect(response).to have_gitlab_http_status(:bad_request)
            end
          end
        end

        context 'with an invalid value' do
          let(:invalid_source) { 'invalid_source' }
          let(:params) { super().merge(source: invalid_source) }

          it 'does not create the workflow' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:bad_request)
          end

          it 'does not track the session event with source in additional_properties' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('agent_platform_session_created')
                    .with(
                      category: 'Ai::DuoWorkflows::CreateWorkflowService',
                      user: user,
                      project: project,
                      additional_properties: { source: invalid_source }
                    )
          end
        end
      end

      context 'when source param is not an allowed value' do
        let(:params) { super().merge(source: 'not_a_valid_source') }

        it 'returns a bad request error' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to eq('source does not have a valid value')
        end
      end

      context 'when source param is not provided' do
        it 'tracks the session created event without source in additional_properties' do
          expect { post api(path, user), params: params }
            .to trigger_internal_events('agent_platform_session_created')
                  .with(
                    category: 'Ai::DuoWorkflows::CreateWorkflowService',
                    user: user,
                    project: project,
                    additional_properties: {}
                  )
        end
      end

      it_behaves_like 'issue and merge request association for workflows'

      include_examples 'container resolution for workflows'
    end

    context 'when failure' do
      shared_examples 'workflow access is forbidden' do
        it 'workflow access is forbidden' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'with a project where the user is not a developer' do
        let(:user) { create(:user, guest_of: project) }

        it_behaves_like 'workflow access is forbidden'
      end

      context 'when duo_features_enabled settings is turned off' do
        before do
          project.project_setting.update!(duo_features_enabled: false)
          project.reload
        end

        it_behaves_like 'workflow access is forbidden'
      end

      context 'when there are not enough credits' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "Usage quota exceeded", reason: :usage_quota_exceeded)
            )
          end
        end

        it_behaves_like 'workflow access is forbidden'
      end

      context 'with namespace-level workflow' do
        let(:container) { { namespace_id: group.id } }

        before do
          group.namespace_settings.update!(duo_features_enabled: false)
          group.reload
        end

        it_behaves_like 'workflow access is forbidden'
      end
    end

    context 'with Duo CLI session gating' do
      let(:cli_headers) { { 'X-Gitlab-Client-Name' => 'Duo CLI' } }

      before do
        ::Ai::Setting.for_organization(current_organization).update!(duo_cli_enabled: false)
      end

      context 'with a Duo CLI session' do
        it 'returns 403 with a message indicating Duo CLI has been disabled' do
          post api(path, user), params: params, headers: cli_headers

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to match('Duo CLI has been disabled by your administrator')
        end

        it 'records an audit event' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(name: 'duo_cli_session_blocked', author: user)
          ).and_call_original

          post api(path, user), params: params, headers: cli_headers

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when the request is not from the Duo CLI' do
        it 'creates the workflow successfully without a client name header' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end

        it 'creates the workflow successfully with a different client name header' do
          post api(path, user), params: params, headers: { 'X-Gitlab-Client-Name' => 'Other Client' }

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when duo_cli_enabled is true' do
        before do
          ::Ai::Setting.for_organization(current_organization).update!(duo_cli_enabled: true)
        end

        it 'creates the workflow when the admin setting is enabled' do
          post api(path, user), params: params, headers: cli_headers

          expect(response).to have_gitlab_http_status(:created)
        end
      end
    end

    context 'when start_workflow is true' do
      before_all do
        project.project_setting.update!(duo_remote_flows_enabled: true)
      end

      shared_examples 'starts duo workflow execution in CI' do
        it 'creates a pipeline to run the workflow' do
          expect_next_instance_of(Ci::CreatePipelineService) do |pipeline_service|
            expect(pipeline_service).to receive(:execute).and_call_original
          end

          post api(path, user), params: params
          expect(json_response['id']).to eq(Ai::DuoWorkflows::Workflow.last.id)
          expect(json_response['workload']['id']).to eq(Ci::Workloads::Workload.last.id)
          expect(::Ci::Pipeline.last.project_id).to eq(project.id)
        end
      end

      shared_examples 'workflow execution blocked in CI' do
        it 'does not start a CI pipeline' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to eq('Can not execute workflow in CI')
        end
      end

      let(:params) do
        {
          project_id: project.id,
          root_namespace_id: group.id,
          start_workflow: true,
          goal: 'Print hello world'
        }
      end

      before do
        allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          allow(client).to receive(:generate_token).and_return(
            ServiceResponse.success(payload: { token: "an-encrypted-token" })
          )
        end
        allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(
              payload: {
                oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'oauth_token')
              }
            )
          )
        end
      end

      it_behaves_like 'starts duo workflow execution in CI'

      it 'uses find_request_namespace for workflow_metadata when namespace params are provided' do
        expect(Gitlab::DuoWorkflow::Client).to receive(:metadata)
          .with(user, namespace: group, project: project)
          .and_call_original

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
      end

      context 'when no namespace params are provided' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'Print hello world'
          }
        end

        it_behaves_like 'starts duo workflow execution in CI'

        it 'falls back to container root_ancestor for workflow_metadata namespace' do
          expect(Gitlab::DuoWorkflow::Client).to receive(:metadata)
            .with(user, namespace: project.root_ancestor, project: project)
            .and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when project_id is not provided' do
        let(:params) do
          {
            root_namespace_id: group.id,
            start_workflow: true,
            goal: 'Print hello world'
          }
        end

        it 'passes nil as project in workflow_metadata' do
          expect(Gitlab::DuoWorkflow::Client).to receive(:metadata)
            .with(user, namespace: group, project: nil)
            .and_call_original

          post api(path, user), params: params

          # StartWorkflowService does not yet support group-level workflows,
          # but the metadata call with correct args is verified above.
          expect(response).to have_gitlab_http_status(:unprocessable_entity)
        end
      end

      context 'when tracking internal events for SAST vulnerability FP detection' do
        let_it_be(:vulnerability) { create(:vulnerability, project: project) }
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: vulnerability.id.to_s,
            workflow_definition: ::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION
          }
        end

        it 'tracks the event with correct properties' do
          allow(Gitlab::InternalEvents).to receive(:track_event).and_call_original

          expect(Gitlab::InternalEvents).to receive(:track_event).with(
            'trigger_sast_vulnerability_fp_detection_workflow',
            hash_including(
              project: project,
              additional_properties: {
                label: 'manual',
                value: vulnerability.id,
                property: vulnerability.severity
              }
            )
          ).and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end

        context 'when vulnerability does not exist' do
          let(:params) do
            {
              project_id: project.id,
              start_workflow: true,
              goal: non_existing_record_id.to_s,
              workflow_definition: ::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION
            }
          end

          it 'does not track the event' do
            expect(Gitlab::InternalEvents).not_to receive(:track_event).with(
              'trigger_sast_vulnerability_fp_detection_workflow',
              anything
            )

            post api(path, user), params: params
          end
        end

        context 'when workflow_definition is not for SAST FP detection' do
          let(:params) do
            {
              project_id: project.id,
              start_workflow: true,
              goal: vulnerability.id.to_s,
              workflow_definition: 'software_development'
            }
          end

          it 'does not track the event' do
            expect(Gitlab::InternalEvents).not_to receive(:track_event).with(
              'trigger_sast_vulnerability_fp_detection_workflow',
              anything
            )

            post api(path, user), params: params
          end
        end

        context 'when start_workflow is not present' do
          let(:params) do
            {
              project_id: project.id,
              goal: vulnerability.id.to_s,
              workflow_definition: ::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION
            }
          end

          it 'does not track the event' do
            expect(Gitlab::InternalEvents).not_to receive(:track_event).with(
              'trigger_sast_vulnerability_fp_detection_workflow',
              anything
            )

            post api(path, user), params: params
          end
        end
      end

      context 'when tracking internal events for SAST vulnerability resolution' do
        let_it_be(:vulnerability) { create(:vulnerability, project: project) }
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: vulnerability.id.to_s,
            workflow_definition: ::Vulnerabilities::TriggerResolutionWorkflowWorker::WORKFLOW_DEFINITION
          }
        end

        it 'tracks the event with correct properties' do
          expect { post api(path, user), params: params }
            .to trigger_internal_events('trigger_sast_vulnerability_resolution_workflow')
                  .with(project: project,
                    category: 'InternalEventTracking',
                    additional_properties: {
                      label: 'manual',
                      value: vulnerability.id,
                      property: vulnerability.severity
                    }
                  )
                  .and increment_usage_metrics('counts.count_total_trigger_sast_vulnerability_resolution_workflow')

          expect(response).to have_gitlab_http_status(:created)
        end

        context 'when vulnerability does not exist' do
          let(:params) do
            {
              project_id: project.id,
              start_workflow: true,
              goal: non_existing_record_id.to_s,
              workflow_definition: ::Vulnerabilities::TriggerResolutionWorkflowWorker::WORKFLOW_DEFINITION
            }
          end

          it 'does not track the event' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('trigger_sast_vulnerability_resolution_workflow')
          end
        end

        context 'when workflow_definition is not for SAST resolution' do
          let(:params) do
            {
              project_id: project.id,
              start_workflow: true,
              goal: vulnerability.id.to_s,
              workflow_definition: 'software_development'
            }
          end

          it 'does not track the event' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('trigger_sast_vulnerability_resolution_workflow')
          end
        end

        context 'when start_workflow is not present' do
          let(:params) do
            {
              project_id: project.id,
              goal: vulnerability.id.to_s,
              workflow_definition: ::Vulnerabilities::TriggerResolutionWorkflowWorker::WORKFLOW_DEFINITION
            }
          end

          it 'does not track the event' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('trigger_sast_vulnerability_resolution_workflow')
          end
        end
      end

      context 'when tracking internal events for Secret Detection vulnerability FP detection' do
        let_it_be(:vulnerability) { create(:vulnerability, project: project) }
        let(:sd_workflow_definition) do
          ::Vulnerabilities::TriggerSecretDetectionFalsePositiveDetectionWorkflowWorker::WORKFLOW_DEFINITION
        end

        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: vulnerability.id.to_s,
            workflow_definition: sd_workflow_definition
          }
        end

        it 'tracks the event with correct properties' do
          event_name = 'trigger_secret_detection_vulnerability_fp_detection_workflow'
          metric_key = "counts.count_total_#{event_name}"

          expect { post api(path, user), params: params }
            .to trigger_internal_events(event_name)
                  .with(project: project,
                    category: 'InternalEventTracking',
                    additional_properties: {
                      label: 'manual',
                      value: vulnerability.id,
                      property: vulnerability.severity
                    }
                  )
                  .and increment_usage_metrics(metric_key)

          expect(response).to have_gitlab_http_status(:created)
        end

        context 'when vulnerability does not exist' do
          let(:params) do
            {
              project_id: project.id,
              start_workflow: true,
              goal: non_existing_record_id.to_s,
              workflow_definition: sd_workflow_definition
            }
          end

          it 'does not track the event' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('trigger_secret_detection_vulnerability_fp_detection_workflow')
          end
        end

        context 'when workflow_definition is not for Secret Detection FP detection' do
          let(:params) do
            {
              project_id: project.id,
              start_workflow: true,
              goal: vulnerability.id.to_s,
              workflow_definition: 'software_development'
            }
          end

          it 'does not track the event' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('trigger_secret_detection_vulnerability_fp_detection_workflow')
          end
        end

        context 'when start_workflow is not present' do
          let(:params) do
            {
              project_id: project.id,
              goal: vulnerability.id.to_s,
              workflow_definition: sd_workflow_definition
            }
          end

          it 'does not track the event' do
            expect { post api(path, user), params: params }
              .not_to trigger_internal_events('trigger_secret_detection_vulnerability_fp_detection_workflow')
          end
        end
      end

      # Only the AI catalog consumer path (which the MR widget uses) has a workflow to
      # attribute the event to. Without one we would emit a row with no project and no
      # merge request, so the event is skipped entirely here.
      context 'when resolve dependency bump is requested without a consumer' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'https://gitlab.example.com/pipelines/1',
            workflow_definition: ::DependencyManagement::SecurityUpdate::
              TriggerResolveDependencyBumpWorkflowWorker::WORKFLOW_DEFINITION
          }
        end

        it 'does not track the event' do
          expect { post api(path, user), params: params }
            .not_to trigger_internal_events('trigger_resolve_dependency_bump_workflow')

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when a code review flow is requested without a consumer' do
        let(:goal) { merge_request.iid.to_s }
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: goal,
            workflow_definition: 'code_review/v1'
          }
        end

        it 'accepts a merge request IID goal' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
          expect(Ai::DuoWorkflows::Workflow.last.goal).to eq(merge_request.iid.to_s)
        end

        context 'when the goal is a merge request URL in the same project' do
          let(:goal) { Gitlab::Routing.url_helpers.project_merge_request_url(project, merge_request) }

          it 'normalizes the goal to the merge request IID' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
            expect(Ai::DuoWorkflows::Workflow.last.goal).to eq(merge_request.iid.to_s)
          end
        end

        context 'when the goal is a merge request URL with a trailing suffix' do
          let(:goal) do
            "#{Gitlab::Routing.url_helpers.project_merge_request_url(project, merge_request)}/diffs#note_123"
          end

          it 'normalizes the goal to the merge request IID' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
            expect(Ai::DuoWorkflows::Workflow.last.goal).to eq(merge_request.iid.to_s)
          end
        end

        context 'when the request has a namespace container' do
          let(:params) do
            {
              namespace_id: group.id,
              start_workflow: true,
              goal: goal,
              workflow_definition: 'code_review/v1'
            }
          end

          it 'returns 400' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['message']).to include('require a project context')
          end
        end

        shared_examples 'rejects the code review goal' do
          it 'returns 400 without creating a workflow' do
            expect { post api(path, user), params: params }
              .not_to change { Ai::DuoWorkflows::Workflow.count }

            expect(response).to have_gitlab_http_status(:bad_request)
            expect(json_response['message']).to include('must be a merge request IID or a full merge request URL')
          end
        end

        context 'when the goal is not a merge request identifier' do
          let(:goal) { 'Review the changes in my merge request' }

          it_behaves_like 'rejects the code review goal'
        end

        context 'when the goal is an IID with no matching merge request' do
          let(:goal) { non_existing_record_iid.to_s }

          it_behaves_like 'rejects the code review goal'
        end

        context 'when the goal is a merge request URL in another project' do
          let(:goal) { "#{Gitlab.config.gitlab.url}/other/project/-/merge_requests/#{merge_request.iid}" }

          it_behaves_like 'rejects the code review goal'
        end
      end

      context 'when duo_remote_flows_enabled settings is turned off' do
        before do
          project.project_setting.update!(duo_remote_flows_enabled: false)
          project.reload
        end

        include_examples 'workflow execution blocked in CI'
      end

      context 'when ci pipeline could not be created' do
        let(:pipeline) do
          instance_double('Ci::Pipeline', created_successfully?: false, full_error_messages: 'full error messages')
        end

        let(:service_response) { ServiceResponse.error(message: 'Error in creating pipeline', payload: pipeline) }

        before do
          allow_next_instance_of(::Ci::CreatePipelineService) do |instance|
            allow(instance).to receive(:execute).and_return(service_response)
          end
        end

        it 'does not start a pipeline to execute workflow' do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message']).to eq('Error in creating workload: full error messages')
        end
      end

      context 'when branch creation fails during CI execution' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'Print hello world',
            source_branch: 'feature-branch'
          }
        end

        before do
          allow_next_instance_of(Ci::Workloads::RunWorkloadService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Error in git branch creation')
            )
          end
        end

        it 'returns error message about branch creation failure' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message']).to eq('Error in git branch creation')
        end
      end

      context 'when start workflow service returns :unprocessable_entity error' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'Print hello world'
          }
        end

        before do
          allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Unprocessable entity error', reason: :unprocessable_entity)
            )
          end
        end

        it 'returns HTTP 422 status code' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message']).to eq('Unprocessable entity error')
        end
      end

      context 'when start workflow service returns :invalid_service_account' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'Print hello world'
          }
        end

        before do
          allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(
                message: 'Service account is required but was not provided.',
                reason: :invalid_service_account
              )
            )
          end
        end

        it 'returns HTTP 403 status code' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to include('Service account is required')
        end
      end

      context 'when start workflow service returns unmapped error reason' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'Print hello world'
          }
        end

        before do
          allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Unknown error occurred', reason: :unknown_error)
            )
          end
        end

        it 'returns HTTP 500 status code as default fallback' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:internal_server_error)
          expect(json_response['message']).to eq('Unknown error occurred')
        end
      end

      context 'when valid additional_context is provided' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'valid additional context',
            additional_context: [
              {
                Category: "agent_user_environment",
                Content: "some content",
                Metadata: "{}"
              }
            ]
          }
        end

        it 'passes additional_context to StartWorkflowService' do
          expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
            workflow: anything,
            params: hash_including(:additional_context)
          ).and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when invalid additional_context is provided' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'valid additional context',
            additional_context: "agent_user_environment"
          }
        end

        it 'passes additional_context to StartWorkflowService' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response).to eq({
            "error" => "additional_context is invalid"
          })
        end
      end

      context 'when source_branch is provided' do
        let(:params) do
          {
            project_id: project.id,
            start_workflow: true,
            goal: 'Print hello world',
            source_branch: 'feature-branch'
          }
        end

        it 'passes source_branch to StartWorkflowService' do
          expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
            workflow: anything,
            params: hash_including(source_branch: 'feature-branch')
          ).and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when environment argument has invalid value' do
        let(:params) { super().merge(environment: 'invalid') }

        it 'returns bad request' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response).to eq({ "error" => "environment does not have a valid value" })
        end
      end

      it_behaves_like 'ai catalog item version workflow creation'

      context 'when foundational flow has no consumer configured' do
        let_it_be_with_reload(:no_consumer_project) { create(:project, :repository, developers: user) }
        let_it_be(:no_consumer_catalog_item) do
          create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'fix_pipeline/v1')
        end

        let_it_be(:foundational_flow_enabled) do
          create(:ai_catalog_enabled_foundational_flow, :for_project,
            project: no_consumer_project,
            catalog_item: no_consumer_catalog_item)
        end

        let(:params) do
          {
            project_id: no_consumer_project.id,
            workflow_definition: 'fix_pipeline/v1',
            goal: 'Fix the pipeline',
            start_workflow: true
          }
        end

        before do
          no_consumer_project.update!(duo_features_enabled: true, duo_remote_flows_enabled: true,
            duo_foundational_flows_enabled: true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
          allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                                .with(no_consumer_project, :duo_workflow).and_return(true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                                .with(no_consumer_project, :foundational_flows).and_return(true)
          allow(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1).to receive(:catalog_item)
            .and_return(no_consumer_catalog_item)
        end

        it 'returns forbidden when no item consumer is configured' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      include_examples 'foundational flow workflow creation'

      context 'when workflow_definition is not a foundational flow' do
        let(:params) do
          {
            project_id: project.id,
            workflow_definition: 'custom_flow',
            goal: 'Implement a cool feature',
            start_workflow: true
          }
        end

        it 'creates a workflow with the composite identity service account' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
          created_workflow = Ai::DuoWorkflows::Workflow.last
          expect(created_workflow.service_account_id).to eq(service_account.id)
        end

        it 'leaves the workflow token unbound' do
          expect_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
            expect(client).to receive(:generate_token).with(flow_config_id: nil, flow_config: nil).and_return(
              ServiceResponse.success(payload: { token: "an-encrypted-token" })
            )
          end

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end

        it 'passes the composite identity service account to CreateWorkflowService' do
          expect(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new).with(
            hash_including(
              params: hash_including(service_account: service_account)
            )
          ).and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end

        context 'when foundational_flows_available? is false' do
          before do
            allow(project).to receive(:foundational_flows_available?).and_return(false)
          end

          it 'still creates the workflow' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end
        end
      end

      include_examples 'ai catalog item consumer workflow execution'
      include_examples 'start workflow execution'

      context 'when ai_catalog_item_consumer_id is provided' do
        let_it_be(:consumer_group) { create(:group) }
        let_it_be(:flow_project) { create(:project, group: consumer_group) }
        let_it_be(:flow) { create(:ai_catalog_flow, :public, project: flow_project) }

        let_it_be(:consumer_service_account) do
          create(:user, :service_account,
            composite_identity_enforced: true,
            provisioned_by_group: consumer_group
          )
        end

        let_it_be(:group_consumer) do
          create(:ai_catalog_item_consumer,
            item: flow,
            group: consumer_group,
            service_account: consumer_service_account
          )
        end

        let_it_be_with_reload(:execution_project) do
          create(:project, :repository, group: consumer_group, developers: user)
        end

        let_it_be(:project_consumer) do
          create(:ai_catalog_item_consumer,
            item: flow,
            project: execution_project,
            parent_item_consumer: group_consumer
          )
        end

        before_all do
          consumer_group.add_developer(user)
          execution_project.update!(duo_features_enabled: true, duo_remote_flows_enabled: true)
          flow_project.update!(duo_features_enabled: true)
        end

        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
          allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                                .with(flow_project, :ai_catalog).and_return(true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                                .with(execution_project, :ai_catalog).and_return(true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                                .with(execution_project, :duo_workflow).and_return(true)
        end

        context 'when the execute service returns an unprocessable_entity error' do
          let(:execute_service_double) do
            instance_double(
              Ai::Catalog::Flows::ExecuteService,
              execute: ServiceResponse.error(
                message: ['No eligible runner'],
                http_status: :unprocessable_entity, # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
                payload: { reason: :no_eligible_runner }
              )
            )
          end

          it 'returns 422 rather than a generic bad request' do
            allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: project_consumer.id,
              start_workflow: true,
              goal: 'Do the thing'
            }

            expect(response).to have_gitlab_http_status(:unprocessable_entity)
          end
        end

        it_behaves_like 'an endpoint with mcp route setting', :create_duo_workflow,
          expected_params: [:project_id, :ai_catalog_item_consumer_id, :goal, :start_workflow],
          status: :created do
          subject do
            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: project_consumer.id,
              start_workflow: true,
              goal: 'Do the thing'
            }
          end

          before do
            allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(
              instance_double(
                ::Ai::Catalog::Flows::ExecuteService,
                execute: ServiceResponse.success(
                  payload: {
                    workflow: build(:duo_workflows_workflow, user: user, project: execution_project),
                    workload_id: 124
                  }
                )
              )
            )
          end
        end

        # source_type is derived from a path check, so without this a change there would
        # silently start tagging every REST-created session as mcp.
        it 'leaves source_type nil for a plain REST create' do
          expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new)
            .with(hash_including(params: hash_including(source_type: nil)))
            .and_return(
              instance_double(
                ::Ai::Catalog::Flows::ExecuteService,
                execute: ServiceResponse.success(
                  payload: {
                    workflow: build(:duo_workflows_workflow, user: user, project: execution_project),
                    workload_id: 124
                  }
                )
              )
            )

          post api("/ai/duo_workflows/workflows", user), params: {
            project_id: execution_project.id,
            ai_catalog_item_consumer_id: project_consumer.id,
            start_workflow: true,
            goal: 'Do the thing'
          }

          expect(response).to have_gitlab_http_status(:created)
        end

        # Every UI entry point creates through a catalog consumer, so this is the path
        # that must carry `source` for it to reach source_type and the tracking event.
        it 'forwards the source param as source_type' do
          expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new)
            .with(hash_including(params: hash_including(source_type: 'fix_pipeline')))
            .and_return(
              instance_double(
                ::Ai::Catalog::Flows::ExecuteService,
                execute: ServiceResponse.success(
                  payload: {
                    workflow: build(:duo_workflows_workflow, user: user, project: execution_project),
                    workload_id: 124
                  }
                )
              )
            )

          post api("/ai/duo_workflows/workflows", user), params: {
            project_id: execution_project.id,
            ai_catalog_item_consumer_id: project_consumer.id,
            start_workflow: true,
            goal: 'Do the thing',
            source: 'fix_pipeline'
          }

          expect(response).to have_gitlab_http_status(:created)
        end

        context 'when noteable params are provided' do
          let(:execute_service_double) do
            fake_workflow = build(:duo_workflows_workflow, user: user, project: execution_project)
            instance_double(
              Ai::Catalog::Flows::ExecuteService,
              execute: ServiceResponse.success(payload: { workflow: fake_workflow, workload_id: 124 })
            )
          end

          it 'forwards merge_request_id to the execute service', :aggregate_failures do
            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(merge_request_id: non_existing_record_iid)
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: project_consumer.id,
              start_workflow: true,
              goal: 'Resolve the merge conflicts',
              merge_request_id: non_existing_record_iid
            }

            expect(response).to have_gitlab_http_status(:created)
          end

          it 'forwards issue_id to the execute service', :aggregate_failures do
            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(issue_id: non_existing_record_iid)
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: project_consumer.id,
              start_workflow: true,
              goal: 'Do the thing',
              issue_id: non_existing_record_iid
            }

            expect(response).to have_gitlab_http_status(:created)
          end
        end

        context 'when callback_hook_id is provided' do
          let_it_be(:catalog_hook) do
            create(:project_hook, project: execution_project, duo_flow_callback_enabled: true)
          end

          before do
            stub_feature_flags(duo_flow_callback_hooks: consumer_group)
          end

          it 'resolves the hook and forwards it to the execute service', :aggregate_failures do
            # ExecuteService is stubbed as in the sibling contexts: the real path needs
            # a running flow. That it forwards the context on to the workflow is covered
            # in ee/spec/services/ai/catalog/flows/execute_service_spec.rb.
            execute_service = instance_double(
              Ai::Catalog::Flows::ExecuteService,
              execute: ServiceResponse.success(payload: {
                workflow: build(:duo_workflows_workflow, user: user, project: execution_project),
                workload_id: 125
              })
            )

            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(messaging_callback_context: {
                'adapter' => 'webhook',
                'hook_id' => catalog_hook.id,
                'client_reference' => 'catalog-run-1'
              })
            ).and_return(execute_service)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: project_consumer.id,
              start_workflow: true,
              goal: 'Do the thing',
              callback_hook_id: catalog_hook.id,
              client_reference: 'catalog-run-1'
            }

            expect(response).to have_gitlab_http_status(:created)
          end

          context 'when the hook is not resolvable in the execution project' do
            let_it_be(:catalog_hook) { create(:project_hook, duo_flow_callback_enabled: true) }

            it 'returns bad request rather than a flow with no callback' do
              post api("/ai/duo_workflows/workflows", user), params: {
                project_id: execution_project.id,
                ai_catalog_item_consumer_id: project_consumer.id,
                start_workflow: true,
                goal: 'Do the thing',
                callback_hook_id: catalog_hook.id
              }

              expect(response).to have_gitlab_http_status(:bad_request)
            end
          end
        end

        context 'when the consumer is for the code review flow' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- needs code review consumer hierarchy
          let_it_be(:code_review_project_consumer) do
            code_review_flow = create(:ai_catalog_flow, :public, project: flow_project,
              foundational_flow_reference: 'code_review/v1')
            code_review_service_account = create(:user, :service_account,
              composite_identity_enforced: true,
              provisioned_by_group: consumer_group
            )
            code_review_group_consumer = create(:ai_catalog_item_consumer,
              item: code_review_flow,
              group: consumer_group,
              service_account: code_review_service_account
            )
            create(:ai_catalog_item_consumer,
              item: code_review_flow,
              project: execution_project,
              parent_item_consumer: code_review_group_consumer
            )
          end

          let_it_be(:target_merge_request) { create(:merge_request, source_project: execution_project) }

          let(:goal) { target_merge_request.iid.to_s }
          let(:params) do
            {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: code_review_project_consumer.id,
              start_workflow: true,
              goal: goal
            }
          end

          let(:execute_service_double) do
            fake_workflow = build(:duo_workflows_workflow, user: user, project: execution_project)
            instance_double(
              Ai::Catalog::Flows::ExecuteService,
              execute: ServiceResponse.success(payload: { workflow: fake_workflow, workload_id: 124 })
            )
          end

          it 'forwards a merge request IID goal as the user prompt' do
            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(user_prompt: target_merge_request.iid.to_s)
            ).and_return(execute_service_double)

            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end

          context 'when the goal is a merge request URL in the same project' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            let(:goal) do
              Gitlab::Routing.url_helpers.project_merge_request_url(execution_project, target_merge_request)
            end

            it 'normalizes the goal to the merge request IID' do
              expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
                project: execution_project,
                current_user: user,
                params: hash_including(user_prompt: target_merge_request.iid.to_s)
              ).and_return(execute_service_double)

              post api(path, user), params: params

              expect(response).to have_gitlab_http_status(:created)
            end
          end

          shared_examples 'rejects the code review goal' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            it 'returns 400 without executing the flow' do
              expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

              post api(path, user), params: params

              expect(response).to have_gitlab_http_status(:bad_request)
              expect(json_response['message']).to include('must be a merge request IID or a full merge request URL')
            end
          end

          context 'when the goal is not a merge request identifier' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            let(:goal) { 'Review the changes in my merge request' }

            it_behaves_like 'rejects the code review goal'
          end

          context 'when the goal is an IID with no matching merge request' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            let(:goal) { non_existing_record_iid.to_s }

            it_behaves_like 'rejects the code review goal'
          end

          context 'when the goal is a merge request URL in another project' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            let(:goal) { Gitlab::Routing.url_helpers.project_merge_request_url(project, merge_request) }

            it_behaves_like 'rejects the code review goal'
          end

          context 'when the request uses a namespace container instead of a project' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            let(:params) do
              {
                namespace_id: consumer_group.id,
                ai_catalog_item_consumer_id: code_review_project_consumer.id,
                start_workflow: true,
                goal: goal
              }
            end

            it 'returns 400' do
              post api(path, user), params: params

              expect(response).to have_gitlab_http_status(:bad_request)
            end
          end
        end

        context 'when tracking internal events for Secret Detection vulnerability FP detection via consumer' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- needs setup for SD consumer hierarchy
          let_it_be(:sd_project_consumer) do
            sd_flow_item = create(:ai_catalog_flow, :public, project: flow_project,
              foundational_flow_reference: 'secrets_fp_detection/v1')
            sd_service_account = create(:user, :service_account,
              composite_identity_enforced: true,
              provisioned_by_group: consumer_group
            )
            sd_group_consumer = create(:ai_catalog_item_consumer,
              item: sd_flow_item,
              group: consumer_group,
              service_account: sd_service_account
            )
            create(:ai_catalog_item_consumer,
              item: sd_flow_item,
              project: execution_project,
              parent_item_consumer: sd_group_consumer
            )
          end

          let_it_be(:vulnerability) { create(:vulnerability, project: execution_project) }

          let(:sd_api_params) do
            {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: sd_project_consumer.id,
              start_workflow: true,
              goal: vulnerability.id.to_s
            }
          end

          before do
            fake_workflow = build(:duo_workflows_workflow, user: user, project: execution_project)

            allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(
              instance_double(
                Ai::Catalog::Flows::ExecuteService,
                execute: ServiceResponse.success(
                  payload: { workflow: fake_workflow, workload_id: 124 }
                )
              )
            )
          end

          it 'tracks the event with correct properties' do
            expect do
              post api("/ai/duo_workflows/workflows", user), params: sd_api_params
            end.to trigger_internal_events(
              'trigger_secret_detection_vulnerability_fp_detection_workflow'
            ).with(project: execution_project,
              category: 'InternalEventTracking',
              additional_properties: {
                label: 'manual',
                value: vulnerability.id,
                property: vulnerability.severity
              }
            )

            expect(response).to have_gitlab_http_status(:created)
          end

          context 'when vulnerability does not exist' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            it 'does not track the event' do
              expect do
                post api("/ai/duo_workflows/workflows", user),
                  params: sd_api_params.merge(goal: non_existing_record_id.to_s)
              end.not_to trigger_internal_events(
                'trigger_secret_detection_vulnerability_fp_detection_workflow'
              )
            end
          end

          context 'when consumer is not for a tracked workflow' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            it 'does not track the event' do
              expect do
                post api("/ai/duo_workflows/workflows", user),
                  params: sd_api_params.merge(ai_catalog_item_consumer_id: project_consumer.id)
              end.not_to trigger_internal_events(
                'trigger_secret_detection_vulnerability_fp_detection_workflow'
              )
            end
          end
        end

        context 'when tracking internal events for resolve dependency bump via consumer' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- needs dependency bump consumer hierarchy
          let_it_be(:rdb_project_consumer) do
            rdb_flow_item = create(:ai_catalog_flow, :public, project: flow_project,
              foundational_flow_reference: 'resolve_dependency_bump/experimental')
            rdb_service_account = create(:user, :service_account,
              composite_identity_enforced: true,
              provisioned_by_group: consumer_group
            )
            rdb_group_consumer = create(:ai_catalog_item_consumer,
              item: rdb_flow_item,
              group: consumer_group,
              service_account: rdb_service_account
            )
            create(:ai_catalog_item_consumer,
              item: rdb_flow_item,
              project: execution_project,
              parent_item_consumer: rdb_group_consumer
            )
          end

          let_it_be(:merge_request) do
            create(:merge_request, source_project: execution_project, target_project: execution_project)
          end

          let(:rdb_api_params) do
            {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: rdb_project_consumer.id,
              start_workflow: true,
              goal: 'https://gitlab.example.com/pipelines/1'
            }
          end

          before do
            fake_workflow = create(:duo_workflows_workflow, user: user, project: execution_project,
              merge_request: merge_request, workflow_definition: 'resolve_dependency_bump/experimental')

            allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(
              instance_double(
                Ai::Catalog::Flows::ExecuteService,
                execute: ServiceResponse.success(
                  payload: { workflow: fake_workflow, workload_id: 124 }
                )
              )
            )
          end

          it 'tracks the event with correct properties' do
            expect do
              post api("/ai/duo_workflows/workflows", user), params: rdb_api_params
            end.to trigger_internal_events(
              'trigger_resolve_dependency_bump_workflow'
            ).with(project: execution_project,
              category: 'InternalEventTracking',
              additional_properties: {
                label: 'manual',
                value: merge_request.id,
                property: '1'
              }
            ).and increment_usage_metrics(
              'counts.count_total_trigger_resolve_dependency_bump_workflow_monthly',
              'counts.count_total_trigger_resolve_dependency_bump_workflow_weekly',
              'counts.count_total_trigger_resolve_dependency_bump_workflow'
            )

            expect(response).to have_gitlab_http_status(:created)
          end

          context 'when the workflow has no merge request' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- inherited from parent
            before do
              fake_workflow = create(:duo_workflows_workflow, user: user, project: execution_project,
                workflow_definition: 'resolve_dependency_bump/experimental')

              allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(
                instance_double(
                  Ai::Catalog::Flows::ExecuteService,
                  execute: ServiceResponse.success(
                    payload: { workflow: fake_workflow, workload_id: 124 }
                  )
                )
              )
            end

            it 'still tracks the event, without the merge request attribution' do
              expect do
                post api("/ai/duo_workflows/workflows", user), params: rdb_api_params
              end.to trigger_internal_events(
                'trigger_resolve_dependency_bump_workflow'
              ).with(project: execution_project,
                category: 'InternalEventTracking',
                additional_properties: { label: 'manual' }
              ).and increment_usage_metrics(
                'counts.count_total_trigger_resolve_dependency_bump_workflow_monthly',
                'counts.count_total_trigger_resolve_dependency_bump_workflow_weekly',
                'counts.count_total_trigger_resolve_dependency_bump_workflow'
              )

              expect(response).to have_gitlab_http_status(:created)
            end
          end
        end

        context 'when injecting secret_detection_context for Secret Detection FP detection' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- needs SD consumer + vulnerability with finding
          let_it_be(:sd_project_consumer) do
            sd_flow_item = create(:ai_catalog_flow, :public, project: flow_project,
              foundational_flow_reference: 'secrets_fp_detection/v1')
            sd_service_account = create(:user, :service_account,
              composite_identity_enforced: true,
              provisioned_by_group: consumer_group
            )
            sd_group_consumer = create(:ai_catalog_item_consumer,
              item: sd_flow_item,
              group: consumer_group,
              service_account: sd_service_account
            )
            create(:ai_catalog_item_consumer,
              item: sd_flow_item,
              project: execution_project,
              parent_item_consumer: sd_group_consumer
            )
          end

          let_it_be(:raw_secret) { 'sk_live_abc123' }
          let_it_be(:vulnerability_with_finding) do
            create(:vulnerability, report_type: :secret_detection, project: execution_project).tap do |v|
              create(:vulnerabilities_finding, :identifier,
                vulnerability: v,
                report_type: :secret_detection,
                project: execution_project,
                raw_metadata: { 'raw_source_code_extract' => raw_secret }.to_json)
            end
          end

          let_it_be(:vulnerability_without_finding) do
            create(:vulnerability, project: execution_project)
          end

          let(:execute_service_double) do
            fake_workflow = build(:duo_workflows_workflow, user: user, project: execution_project)
            instance_double(
              Ai::Catalog::Flows::ExecuteService,
              execute: ServiceResponse.success(payload: { workflow: fake_workflow, workload_id: 124 })
            )
          end

          before do
            stub_licensed_features(security_dashboard: true)
          end

          it 'passes both legacy and typed envelopes via additional_context', :aggregate_failures do
            expected_content = %({"secret_value":"#{raw_secret}"})

            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(
                additional_context: [
                  { "Category" => 'secret_detection_context', "Content" => expected_content },
                  { "Category" => 'agent_platform_secrets_fp_detection_context', "Content" => expected_content }
                ]
              )
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: sd_project_consumer.id,
              start_workflow: true,
              goal: vulnerability_with_finding.id.to_s
            }

            expect(response).to have_gitlab_http_status(:created)
          end

          it 'preserves caller-supplied additional_context alongside the injected envelope', :aggregate_failures do
            caller_context = [{ Category: 'agent_user_environment', Content: '{"key":"value"}' }]

            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(
                additional_context: a_collection_containing_exactly(
                  a_hash_including('Category' => 'agent_user_environment'),
                  a_hash_including("Category" => 'secret_detection_context'),
                  a_hash_including("Category" => 'agent_platform_secrets_fp_detection_context')
                )
              )
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: sd_project_consumer.id,
              start_workflow: true,
              goal: vulnerability_with_finding.id.to_s,
              additional_context: caller_context
            }

            expect(response).to have_gitlab_http_status(:created)
          end

          it 'does not inject when the vulnerability has no raw token value', :aggregate_failures do
            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(additional_context: nil)
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: sd_project_consumer.id,
              start_workflow: true,
              goal: vulnerability_without_finding.id.to_s
            }

            expect(response).to have_gitlab_http_status(:created)
          end

          it 'does not inject when the user lacks permission to read the vulnerability', :aggregate_failures do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?)
              .with(user, :read_vulnerability, vulnerability_with_finding)
              .and_return(false)

            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(additional_context: nil)
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: sd_project_consumer.id,
              start_workflow: true,
              goal: vulnerability_with_finding.id.to_s
            }

            expect(response).to have_gitlab_http_status(:created)
          end

          it 'does not inject for non-secret-detection consumers', :aggregate_failures do
            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
              project: execution_project,
              current_user: user,
              params: hash_including(additional_context: nil)
            ).and_return(execute_service_double)

            post api("/ai/duo_workflows/workflows", user), params: {
              project_id: execution_project.id,
              ai_catalog_item_consumer_id: project_consumer.id,
              start_workflow: true,
              goal: vulnerability_with_finding.id.to_s
            }

            expect(response).to have_gitlab_http_status(:created)
          end
        end
      end

      context 'when OAuth token creation fails' do
        before do
          allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
            allow(service).to receive(:generate_oauth_token_with_composite_identity_support)
              .and_return(ServiceResponse.error(message: 'OAuth token creation failed', http_status: :forbidden)) # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
          end
        end

        it 'returns api error' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when workflow token creation fails' do
        context 'with usage quota exceeded error code' do
          before do
            allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
              allow(service).to receive(:generate_workflow_token)
                .and_return(ServiceResponse.error(message: 'Consumer does not have sufficient ' \
                                                    'credits for this request. Error code: USAGE_QUOTA_EXCEEDED'))
            end
          end

          it 'returns forbidden with specific message' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:forbidden)
            expect(json_response['message']).to eq(
              "You don't have enough GitLab Credits to run this flow. Contact your " \
                "administrator for more credits."
            )
          end
        end

        context 'with any other error' do
          before do
            allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
              allow(service).to receive(:generate_workflow_token)
                                  .and_return(ServiceResponse.error(message: 'workflow token creation failed'))
            end
          end

          it 'returns api error' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:bad_request)
          end
        end
      end

      context 'when Langsmith-Trace header is provided' do
        it 'passes langsmith_trace to StartWorkflowService' do
          expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
            workflow: anything,
            params: hash_including(langsmith_trace: 'trace-id-456')
          ).and_call_original

          post api(path, user), params: params, headers: { 'Langsmith-Trace' => 'trace-id-456' }

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when Langsmith-Trace header is not provided' do
        it 'does not pass langsmith_trace to StartWorkflowService' do
          expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
            workflow: anything,
            params: hash_not_including(:langsmith_trace)
          ).and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      it 'passes service_account from composite identity to StartWorkflowService' do
        expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
          workflow: anything,
          params: hash_including(:service_account)
        ).and_call_original

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
      end

      context 'when composite identity does not resolve a service account' do
        before do
          stub_feature_flags(enforce_composite_identity_for_api_started_workflows: false)
          allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor)
            .with(user).and_return(user)
        end

        it 'falls back to the duo workflow service account' do
          expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
            workflow: anything,
            params: hash_including(service_account: service_account)
          ).and_call_original

          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
        end

        it 'ensures the duo workflow service account has project access' do
          expect(::Ai::ServiceAccountMemberAddService).to receive(:new)
            .with(project, service_account).and_call_original

          post api(path, user), params: params
        end

        context 'when duo workflow service account is also not configured' do
          before do
            ::Ai::Setting.for_organization(project.organization).update!(duo_workflow_service_account_user_id: nil)
          end

          it 'returns forbidden' do
            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:forbidden)
            expect(json_response['message']).to include('Service account is required')
          end
        end
      end
    end

    context 'with callback_hook_id' do
      let_it_be(:group_hook) { create(:group_hook, group: group, duo_flow_callback_enabled: true) }
      let_it_be(:project_hook) { create(:project_hook, project: project, duo_flow_callback_enabled: true) }

      before do
        stub_licensed_features(group_webhooks: true)
        stub_feature_flags(duo_flow_callback_hooks: group)
        allow(Gitlab::AiGateway).to receive(:public_headers).and_return({})
      end

      shared_examples 'attaches the callback hook' do
        it 'persists the hook in messaging_callback_context' do
          post api(path, user), params: params.merge(callback_hook_id: hook.id)

          expect(response).to have_gitlab_http_status(:created)
          expect(Ai::DuoWorkflows::Workflow.last.messaging_callback_context).to include(
            'adapter' => 'webhook',
            'hook_id' => hook.id
          )
        end
      end

      shared_examples 'rejects the callback hook' do
        it 'returns bad request rather than a workflow with no callback' do
          post api(path, user), params: params.merge(callback_hook_id: hook.id)

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'with a hook on the project itself' do
        let(:hook) { project_hook }

        it_behaves_like 'attaches the callback hook'
      end

      # The flow runs in a project, the hook lives on its group: the shape that
      # regressed when ancestor resolution was dropped from the finder.
      context 'with a hook on an ancestor group' do
        let(:hook) { group_hook }

        it_behaves_like 'attaches the callback hook'

        context 'when group webhooks are not licensed' do
          before do
            stub_licensed_features(group_webhooks: false)
          end

          it_behaves_like 'rejects the callback hook'
        end
      end

      context 'when client_reference is also provided' do
        it 'echoes it back through the callback context' do
          post api(path, user), params: params.merge(callback_hook_id: group_hook.id, client_reference: 'run-abc')

          expect(response).to have_gitlab_http_status(:created)
          expect(Ai::DuoWorkflows::Workflow.last.messaging_callback_context['client_reference']).to eq('run-abc')
        end
      end

      # client_reference is echoed into every callback payload, so it is bounded.
      context 'when client_reference is longer than the allowed limit' do
        it 'returns bad request' do
          post api(path, user), params: params.merge(callback_hook_id: group_hook.id, client_reference: 'a' * 256)

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when the hook does not have Duo flow callbacks enabled' do
        let(:hook) { create(:group_hook, group: group) }

        it_behaves_like 'rejects the callback hook'
      end

      context 'when the hook belongs to another hierarchy' do
        let(:hook) { create(:group_hook, duo_flow_callback_enabled: true) }

        it_behaves_like 'rejects the callback hook'
      end

      context 'when no hook has that id' do
        let(:hook) { instance_double(GroupHook, id: non_existing_record_id) }

        it_behaves_like 'rejects the callback hook'
      end

      # A silent 201 here would leave the client waiting for events that are
      # never sent, which is worse than an explicit failure.
      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(duo_flow_callback_hooks: false)
        end

        let(:hook) { group_hook }

        it_behaves_like 'rejects the callback hook'
      end

      context 'when the flag is enabled for a different namespace' do
        before do
          stub_feature_flags(duo_flow_callback_hooks: create(:group))
        end

        let(:hook) { group_hook }

        it_behaves_like 'rejects the callback hook'
      end

      context 'when Duo Agent Platform is unavailable' do
        before do
          allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)
        end

        let(:hook) { group_hook }

        it_behaves_like 'rejects the callback hook'
      end

      context 'without a callback_hook_id' do
        it 'creates the workflow with no callback context' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:created)
          expect(Ai::DuoWorkflows::Workflow.last.messaging_callback_context).to be_blank
        end
      end

      # Everything above stops at the persisted callback context. This is the only
      # example that exercises the claim that delivery reuses the webhook stack.
      context 'when the flow reaches a terminal state', :sidekiq_inline do
        let_it_be(:delivery_hook) do
          create(:project_hook, project: project, duo_flow_callback_enabled: true,
            url: 'https://callbacks.example.com/duo')
        end

        let(:delivered) { [] }

        before do
          # Keep the final message on the plain checkpoint rather than the
          # incremental blob store: checkpoint storage is not what is under test.
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)

          stub_full_request(delivery_hook.url, method: :post, port: 443).to_return do |request|
            delivered << request
            { status: 200, body: '' }
          end
        end

        it 'POSTs the lifecycle events through WebHookService and logs each delivery' do
          post api(path, user), params: params.merge(callback_hook_id: delivery_hook.id, client_reference: 'run-1')

          expect(response).to have_gitlab_http_status(:created)

          workflow = Ai::DuoWorkflows::Workflow.last
          workflow.start!

          # flow.completed carries the agent's final message, which CallbackWorker
          # reads off the last checkpoint. Without one the flow reports no_response.
          create(:duo_workflows_checkpoint, workflow: workflow, project: project,
            checkpoint: { 'channel_values' => {
              'ui_chat_log' => [{ 'message_type' => 'agent', 'content' => 'All done!' }]
            } })

          workflow.finish!

          bodies = delivered.map { |request| Gitlab::Json.parse(request.body) }
          expect(bodies.map { |body| body['event'] }).to eq(%w[flow.started flow.completed])

          completed = bodies.last
          expect(completed).to include(
            'object_kind' => 'duo_workflow',
            'version' => '1',
            'client_reference' => 'run-1'
          )
          expect(completed['result']).to eq({ 'message' => 'All done!' })
          expect(completed['workflow']).to include('id' => workflow.id, 'status' => 'finished')
          expect(completed['project']).to include('id' => project.id)
          expect(completed['user']).to include('id' => user.id)

          # The signature headers are added by WebHookService, so finding them here
          # is the evidence that delivery went through the shared webhook stack.
          expect(delivered.last.headers).to include(
            'X-Gitlab-Event' => 'Duo Flow Callback',
            'Webhook-Id' => completed['event_id'],
            'Idempotency-Key' => completed['event_id']
          )
          expect(bodies.map { |body| body['event_id'] }.uniq.size).to eq(2)

          logs = WebHookLog.where(web_hook: delivery_hook)
          expect(logs.count).to eq(2)
          expect(logs.map { |log| log.request_data['event'] })
            .to contain_exactly('flow.started', 'flow.completed')
        end
      end
    end
  end

  describe 'POST /ai/duo_workflows/direct_access' do
    let(:path) { '/ai/duo_workflows/direct_access' }

    let(:post_without_params) { post api(path, user) }
    let(:post_with_definition) { post api(path, user), params: { workflow_definition: workflow_definition } }

    let(:post_with_params) do
      post api(path, user), params: { workflow_definition: workflow_definition, root_namespace_id: namespace_id }
    end

    before do
      allow(Gitlab.config.duo_workflow).to receive(:service_url).and_return duo_workflow_service_url

      stub_config(duo_workflow: {
        service_url: duo_workflow_service_url,
        secure: true
      })
    end

    shared_context 'when tokens are generated' do
      let(:gitlab_rails_token_expires_at) { 2.hours.from_now.to_i }
      let(:duo_workflow_service_token_expires_at) { 1.hour.from_now.to_i }

      before do
        allow(::CloudConnector).to receive(:ai_headers).with(user, namespace_ids: anything, subject: anything)
          .and_return({ header_key: 'header_value' })
        allow_next_instance_of(::Gitlab::Tracking::StandardContext) do |context|
          allow(context).to receive(:gitlab_team_member?).and_return(false)
          allow(context).to receive(:gitlab_team_member?).with(user.id).and_return(true)
        end
        allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(payload: {
              oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'oauth_token',
                expires_at: gitlab_rails_token_expires_at)
            })
          )
        end
        allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          allow(client).to receive(:generate_token).and_return(
            ServiceResponse.success(payload: { token: 'duo_workflow_token',
                                               expires_at: duo_workflow_service_token_expires_at })
          )
        end

        allow(::Gitlab::SubscriptionPortal::Client).to receive(:verify_usage_quota).and_return({ success: true })
      end
    end

    shared_context 'when usage quota check passes' do
      before do
        allow_next_instance_of(::Ai::UsageQuotaService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success)
        end
      end
    end

    context 'when identity verification is required' do
      include_context 'when identity verification blocks the user'
      include_context 'when usage quota check passes'

      it 'refuses to issue a token and names identity verification', :aggregate_failures do
        post_without_params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when rate limited' do
      it 'returns api error' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_return(true)

        post_without_params

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(response.headers)
          .to include(
            'Retry-After' => Gitlab::ApplicationRateLimiter.period_for(:duo_workflow_direct_access)
          )
      end
    end

    context 'when root_namespace_id params is not passed' do
      context 'when on SaaS' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)

          allow_next_instance_of(::Ai::UsageQuotaService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Namespace is required'))
          end
        end

        it 'returns error that root_namespace_id is required' do
          post_with_definition

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to include('Namespace is required')
        end
      end

      context 'when on Self-managed instance' do
        include_context 'when tokens are generated'

        it 'successfully generates a direct access token' do
          post_with_definition

          expect(response).to have_gitlab_http_status(:created)
        end
      end
    end

    context 'when CreateOauthAccessTokenService returns error' do
      include_context 'when usage quota check passes'

      it 'returns api error' do
        expect_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
          expect(service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'Duo workflow is not enabled for user', http_status: :forbidden) # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
          )
        end

        post_without_params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when DuoWorkflowService returns error' do
      include_context 'when usage quota check passes'

      it 'returns api error' do
        expect_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          expect(client).to receive(:generate_token).and_return(
            ServiceResponse.error(message: "could not generate token")
          )
        end

        post_without_params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when usage quota check fails' do
      before do
        allow_next_instance_of(::Ai::UsageQuotaService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'Usage quota exceeded', reason: :usage_quota_exceeded)
          )
        end
      end

      it 'returns error that root_namespace_id is required' do
        post_with_definition

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('USAGE_QUOTA_EXCEEDED: Usage quota exceeded')
      end
    end

    context 'when usage billing is forbidden' do
      before do
        allow_next_instance_of(::Ai::UsageQuotaService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'Usage billing not available', reason: :usage_billing_forbidden)
          )
        end
      end

      it 'returns forbidden with usage billing forbidden message' do
        post_with_definition

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('USAGE_BILLING_FORBIDDEN: Usage billing not available')
      end
    end

    context 'when namespace is missing from quota check' do
      it 'returns forbidden with actionable namespace missing message' do
        expect_next_instance_of(::Ai::UsageQuotaService) do |service|
          expect(service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'Namespace is required', reason: :namespace_missing)
          )
        end

        post_with_definition

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('default GitLab Duo namespace')
        expect(json_response['message']).to include('preferences')
      end
    end

    context 'when workflow_definition param is passed' do
      let(:workflow_definition) { "software_development" }

      it 'calls usage quota service with the user and the root namespace' do
        expect(::Ai::UsageQuotaService).to receive(:new)
          .with(user: user, namespace: group)

        post_with_definition
      end
    end

    context 'when success' do
      let(:namespace_id) { group.id }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      include_context 'when tokens are generated'

      it 'returns access payload' do
        stub_feature_flags(duo_workflow_extended_logging: false)

        post_with_params

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['gitlab_rails']['base_url']).to eq(Gitlab.config.gitlab.url)
        expect(json_response['gitlab_rails']['token']).to eq('oauth_token')
        expect(json_response['gitlab_rails']['token_expires_at']).to eq(gitlab_rails_token_expires_at)
        expect(json_response['duo_workflow_service']['base_url']).to eq("duo-workflow-service.example.com:50052")
        expect(json_response['duo_workflow_service']['token']).to eq('duo_workflow_token')
        expect(json_response['duo_workflow_service']['headers']['header_key']).to eq("header_value")
        expect(json_response['duo_workflow_service']['secure']).to eq(
          Gitlab::DuoWorkflow::Client.secure?(feature_setting: nil)
        )
        expect(json_response['duo_workflow_service']['token_expires_at']).to eq(duo_workflow_service_token_expires_at)
        expect(json_response['workflow_metadata']['extended_logging']).to be(false)
        expect(json_response['workflow_metadata']['is_team_member']).to be(true)
        expect(json_response['workflow_metadata']['rootNamespaceId']).to eq(group.id.to_s)
      end

      it_behaves_like 'authorizing granular token permissions',
        :create_duo_workflow_direct_access_token do
        let(:boundary_object) { :user }
        let(:request) do
          post api(path, personal_access_token: pat),
            params: { workflow_definition: workflow_definition, root_namespace_id: namespace_id }
        end
      end

      it 'passes the governed project id to the duo workflow service headers' do
        project_in_group = create(:project, group: group)
        project_in_group.add_developer(user)

        expect(Gitlab::AiGateway).to receive(:public_headers)
          .with(hash_including(project_id: project_in_group.id))
          .and_call_original

        post api(path, user), params: {
          workflow_definition: workflow_definition,
          root_namespace_id: namespace_id,
          project_id: project_in_group.id
        }

        expect(response).to have_gitlab_http_status(:created)
      end

      it 'passes a nil project id when no project is in scope' do
        expect(Gitlab::AiGateway).to receive(:public_headers)
          .with(hash_including(project_id: nil))
          .and_call_original

        post api(path, user), params: {
          workflow_definition: workflow_definition,
          root_namespace_id: namespace_id
        }

        expect(response).to have_gitlab_http_status(:created)
      end

      context 'when duo_workflow_extended_logging is disabled' do
        before do
          stub_feature_flags(duo_workflow_extended_logging: false)
        end

        it 'returns workflow_metadata.extended_logging: false' do
          post_without_params

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['workflow_metadata']['extended_logging']).to be(false)
        end

        context 'when namespace has ai_usage_data_collection_enabled' do
          before do
            group.update!(ai_usage_data_collection_enabled: true)
          end

          it 'returns workflow_metadata.extended_logging: true' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['workflow_metadata']['extended_logging']).to be(true)
          end
        end
      end

      context 'when authenticated with a token that has the ai_workflows scope' do
        it 'is forbidden' do
          post api(path, oauth_access_token: ai_workflows_oauth_token)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when organization is assigned' do
        before do
          allow(Current).to receive(:organization_assigned).and_return(true)
        end

        it 'includes organization_id in duo workflow service headers' do
          post_with_params

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['duo_workflow_service']['headers'])
            .to include('x-gitlab-organization-id' => current_organization.id.to_s)
        end
      end

      context 'when organization is not assigned' do
        before do
          allow(Current).to receive(:organization_assigned).and_return(false)
        end

        it 'does not include organization_id in duo workflow service headers' do
          post_with_params

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['duo_workflow_service']['headers'])
            .not_to have_key('x-gitlab-organization-id')
        end
      end

      context 'for server_capabilities' do
        before do
          stub_feature_flags(duo_workflow_write_incremental_only: false)
        end

        context 'when DWS returns empty capabilities' do
          before do
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: []
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
          end

          it 'returns only default Rails capabilities' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities'])
              .to match_array(%w[job_trace_pagination tool_call_approval_source incremental_checkpoints])
          end

          context 'when advanced search is enabled' do
            before do
              allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
                .with(scope: group).and_return(true)
            end

            it 'returns advanced_search and default Rails capabilities' do
              post_with_params

              expect(response).to have_gitlab_http_status(:created)
              expect(json_response['server_capabilities'])
                .to match_array(
                  %w[job_trace_pagination advanced_search tool_call_approval_source incremental_checkpoints]
                )
            end
          end

          context 'when write_incremental_only is enabled' do
            before do
              stub_feature_flags(duo_workflow_write_incremental_only: group)
            end

            it 'advertises incremental_checkpoints_only alongside default Rails capabilities' do
              post_with_params

              expect(response).to have_gitlab_http_status(:created)
              expect(json_response['server_capabilities'])
                .to match_array(
                  %w[job_trace_pagination incremental_checkpoints_only tool_call_approval_source
                    incremental_checkpoints]
                )
            end
          end
        end

        context 'when DWS returns capabilities' do
          before do
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
          end

          it 'returns union of Rails and DWS capabilities' do
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
              .with(scope: group).and_return(true)

            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).to match_array(
              %w[job_trace_pagination advanced_search tool_call_approval tool_call_pattern_approval
                approve_for_session tool_call_approval_source incremental_checkpoints]
            )
          end

          it 'returns DWS capabilities and default Rails capabilities' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).to match_array(
              %w[job_trace_pagination tool_call_approval tool_call_pattern_approval approve_for_session
                tool_call_approval_source incremental_checkpoints]
            )
          end
        end

        context 'when tool_approval_for_session is disabled' do
          before do
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: false)
          end

          it 'filters out tool_call_approval and tool_call_pattern_approval from capabilities' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities'])
              .to match_array(
                %w[job_trace_pagination approve_for_session tool_call_approval_source incremental_checkpoints]
              )
          end
        end

        # clean_gitlab_redis_rate_limiting keeps this extra request from eating
        # the shared 50/min duo_workflow_direct_access budget, which later
        # examples in this file (the execute endpoint) sit close to already.
        context 'when duo_auto_mode is enabled for the namespace', :clean_gitlab_redis_rate_limiting do
          before do
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: []
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
            group.reload.namespace_settings.update!(duo_auto_mode_enabled: true)
          end

          it 'advertises duo_auto_mode alongside default Rails capabilities' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities'])
              .to match_array(%w[job_trace_pagination duo_auto_mode tool_call_approval_source incremental_checkpoints])
          end
        end

        context 'when the duo_auto_mode feature flag is disabled', :clean_gitlab_redis_rate_limiting do
          before do
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: []
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
            stub_feature_flags(duo_auto_mode: false)
            group.reload.namespace_settings.update!(duo_auto_mode_enabled: true)
          end

          it 'does not advertise duo_auto_mode' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).not_to include('duo_auto_mode')
          end
        end

        context 'when root_namespace has no namespace_settings' do
          before do
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
            NamespaceSetting.where(namespace_id: group.id).delete_all
          end

          it 'filters out tool_call_approval and tool_call_pattern_approval from capabilities' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities'])
              .to match_array(
                %w[job_trace_pagination approve_for_session tool_call_approval_source incremental_checkpoints]
              )
          end
        end

        context 'when subgroup has tool_approval_for_session disabled while root is ON' do
          let_it_be_with_refind(:subgroup) { create(:group, parent: group) }

          before_all do
            subgroup.add_maintainer(user)
          end

          before do
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
            subgroup.namespace_settings.update!(tool_approval_for_session_enabled: false)
          end

          it 'filters out tool_call_approval and tool_call_pattern_approval because subgroup setting is OFF' do
            post api(path, user),
              params: { workflow_definition: workflow_definition, root_namespace_id: group.id },
              headers: { 'X-Gitlab-Namespace-Id' => subgroup.id.to_s }

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities'])
              .to match_array(
                %w[job_trace_pagination approve_for_session tool_call_approval_source incremental_checkpoints]
              )
          end
        end

        context 'when subgroup inherits tool_approval_for_session from root (nil value)' do
          let(:inheriting_subgroup) { create(:group, parent: group) }

          before do
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
            inheriting_subgroup.add_maintainer(user)
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
          end

          it 'includes tool_call_approval and tool_call_pattern_approval because subgroup inherits from root' do
            post api(path, user),
              params: { workflow_definition: workflow_definition, root_namespace_id: group.id },
              headers: { 'X-Gitlab-Namespace-Id' => inheriting_subgroup.id.to_s }

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).to include('tool_call_approval', 'tool_call_pattern_approval')
          end
        end

        context 'when namespace_id header references a namespace user cannot access' do
          let(:inaccessible_subgroup) { create(:group, :private) }

          before do
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
            # User is NOT a member of inaccessible_subgroup
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
          end

          it 'falls back to root namespace for tool approval check' do
            post api(path, user),
              params: { workflow_definition: workflow_definition, root_namespace_id: group.id },
              headers: { 'X-Gitlab-Namespace-Id' => inaccessible_subgroup.id.to_s }

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).to include('tool_call_approval', 'tool_call_pattern_approval')
          end
        end

        context 'when namespace_id header references a non-existent namespace' do
          before do
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval tool_call_pattern_approval approve_for_session]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
          end

          it 'falls back to root namespace for tool approval check' do
            post api(path, user),
              params: { workflow_definition: workflow_definition, root_namespace_id: group.id },
              headers: { 'X-Gitlab-Namespace-Id' => non_existing_record_id.to_s }

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).to include('tool_call_approval', 'tool_call_pattern_approval')
          end
        end

        context 'when DWS supports capabilities Rails does not' do
          before do
            group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
            allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
              allow(client).to receive(:generate_token).and_return(
                ServiceResponse.success(payload: {
                  token: 'duo_workflow_token',
                  expires_at: 1.hour.from_now.to_i,
                  capabilities: %w[tool_call_approval dws_only_feature]
                })
              )
            end
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
              .with(scope: group).and_return(true)
          end

          it 'returns union including all DWS capabilities' do
            post_with_params

            expect(response).to have_gitlab_http_status(:created)
            expect(json_response['server_capabilities']).to match_array(
              %w[job_trace_pagination advanced_search tool_call_approval dws_only_feature tool_call_approval_source
                incremental_checkpoints]
            )
          end
        end
      end
    end

    # Regression: direct_access used to mint the token with no container, giving an empty policy.
    context 'when the requested namespace has governance rules' do
      let(:namespace_id) { group.id }

      include_context 'when tokens are generated'
      include_context 'when usage quota check passes'

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      context 'with an Always-Deny rule on the namespace' do
        before do
          create(:ai_tool_rule, namespace: group, tool_name: 'create_issue', web_access: :deny)
        end

        it 'resolves governance for the requested namespace when minting the token' do
          expect(::Ai::ToolRules::ResolutionService).to receive(:new)
            .with(namespace: group.root_ancestor, surface: :web, project: nil)
            .and_call_original

          post_with_params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'with an Always-Ask (HITL) rule on the namespace' do
        before do
          create(:ai_tool_rule, namespace: group, tool_name: 'create_issue', web_access: :ask)
        end

        it 'gates the tool for HITL: neither pre-approved nor denied in the token', :aggregate_failures do
          resolved = nil
          allow_next_instance_of(::Ai::ToolRules::ResolutionService) do |service|
            allow(service).to receive(:execute).and_wrap_original do |original|
              result = original.call
              resolved = result.payload if result.success?
              result
            end
          end

          post_with_params

          expect(response).to have_gitlab_http_status(:created)
          expect(resolved[:denied_tools]).not_to include('create_work_item')
          expect(resolved[:pre_approved_tools]).not_to include('create_work_item')
        end
      end

      context 'with a project-scoped rule and project_id supplied' do
        let(:post_with_project) do
          post api(path, user),
            params: {
              workflow_definition: workflow_definition,
              root_namespace_id: namespace_id,
              project_id: project.id
            }
        end

        before do
          create(:ai_tool_rule, namespace: group, project: project, tool_name: 'create_issue', web_access: :deny)
        end

        it 'resolves governance against the project (project-aware container)' do
          expect(::Ai::ToolRules::ResolutionService).to receive(:new)
            .with(namespace: group.root_ancestor, surface: :web, project: project)
            .and_call_original

          post_with_project

          expect(response).to have_gitlab_http_status(:created)
        end
      end
    end

    # Confirms the resolved policy reaches the DWS client, not just that governance resolves.
    context 'when propagating the resolved policy to the DWS client' do
      let(:namespace_id) { group.id }

      include_context 'when usage quota check passes'

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        create(:ai_tool_rule, namespace: group, tool_name: 'create_issue', web_access: :deny)

        allow(::CloudConnector).to receive(:ai_headers).and_return({ header_key: 'header_value' })
        allow_next_instance_of(::Gitlab::Tracking::StandardContext) do |context|
          allow(context).to receive(:gitlab_team_member?).and_return(false)
        end
        allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(payload: {
              oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'oauth_token',
                expires_at: 2.hours.from_now.to_i)
            })
          )
        end
      end

      it 'passes the namespace deny policy to the Duo Workflow Service client', :aggregate_failures do
        captured = nil
        allow(::Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).and_wrap_original do |_original, **kwargs|
          captured = kwargs
          instance_double(::Ai::DuoWorkflow::DuoWorkflowService::Client).tap do |client|
            allow(client).to receive(:generate_token).and_return(
              ServiceResponse.success(payload: { token: 'duo_workflow_token', expires_at: 1.hour.from_now.to_i })
            )
          end
        end

        post_with_params

        expect(response).to have_gitlab_http_status(:created)
        expect(captured[:denied_tools]).to include('create_work_item')
      end
    end

    # A project_id-only request skips validate_namespace_context!, so the project must not
    # be allowed to swap the governance namespace to one the caller chose (governance bypass).
    context 'when project_id references a project outside the governing namespace' do
      let_it_be(:foreign_group) { create(:group) }
      let_it_be(:foreign_project) { create(:project, group: foreign_group) }

      include_context 'when tokens are generated'
      include_context 'when usage quota check passes'
      include_context 'with user governing namespace' do
        let(:governing_namespace) { group }
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        create(:ai_tool_rule, namespace: group, tool_name: 'create_issue', web_access: :deny)
      end

      it 'resolves governance against the governing namespace, ignoring the foreign project' do
        expect(::Ai::ToolRules::ResolutionService).to receive(:new)
          .with(namespace: group.root_ancestor, surface: :web, project: nil)
          .and_call_original

        post api(path, user), params: { workflow_definition: workflow_definition, project_id: foreign_project.id }

        expect(response).to have_gitlab_http_status(:created)
      end

      it 'computes HITL capabilities from the governing namespace, not the foreign project', :aggregate_failures do
        group.reload.namespace_settings.update!(tool_approval_for_session_enabled: true)
        foreign_project.project_setting.update!(tool_approval_for_session_enabled: false)
        allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
        allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          allow(client).to receive(:generate_token).and_return(
            ServiceResponse.success(payload: {
              token: 'duo_workflow_token', expires_at: 1.hour.from_now.to_i,
              capabilities: %w[tool_call_approval tool_call_pattern_approval]
            })
          )
        end

        post api(path, user), params: { workflow_definition: workflow_definition, project_id: foreign_project.id }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['server_capabilities']).to include('tool_call_approval', 'tool_call_pattern_approval')
      end
    end
  end

  describe 'GET /ai/duo_workflows/ws' do
    let(:path) { '/ai/duo_workflows/ws' }
    let(:self_hosted_duo_workflow_service_url) { 'self-hosted-dap-service-url:50052' }
    let(:default_duo_workflow_service_url) { 'cloud.gitlab.com:50052' }

    include_context 'workhorse headers'
    include_context 'with user governing namespace' do
      let(:governing_namespace) { group }
    end

    subject(:get_response) { get api(path, user), headers: workhorse_headers, params: { workflow_definition: 'chat' } }

    before do
      allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.success(payload: {
            oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'oauth_token')
          })
        )
      end

      allow(Gitlab::DuoWorkflow::Client).to receive_messages(
        self_hosted_url: self_hosted_duo_workflow_service_url,
        default_service_url: default_duo_workflow_service_url,
        secure?: true
      )

      allow(Gitlab.config.duo_workflow).to receive(:service_url).and_return(duo_workflow_service_url)

      allow(::CloudConnector::Tokens).to receive(:get).and_return('token')
    end

    shared_examples 'ServiceURI has the right value' do |with_self_hosted_setting|
      context 'with a duo workflow service url set' do
        it 'routes to the right service uri' do
          get_response

          if with_self_hosted_setting
            expect(json_response['DuoWorkflow']['Service']['URI']).to eq(self_hosted_duo_workflow_service_url)
          else
            expect(json_response['DuoWorkflow']['Service']['URI']).to eq(duo_workflow_service_url)
          end
        end
      end

      context 'with no duo workflow service url set' do
        let(:duo_workflow_service_url) { nil }

        it 'routes to the right service uri' do
          get_response

          if with_self_hosted_setting
            expect(json_response['DuoWorkflow']['Service']['URI']).to eq(self_hosted_duo_workflow_service_url)
          else
            expect(json_response['DuoWorkflow']['Service']['URI']).to eq(default_duo_workflow_service_url)
          end
        end
      end
    end

    context 'when identity verification is required' do
      include_context 'when identity verification blocks the user'

      it 'refuses the connection and names identity verification', :aggregate_failures do
        get_response

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when user is authenticated' do
      # Listed literally so adding a `readOnlyHint` for pre-approval gets a deliberate review.
      # Sorted alphabetically to avoid merge conflicts
      let(:mcp_preapproved_tools) do
        %w[
          get_artifact_file
          get_commit
          get_duo_session
          get_duo_workflow_status
          get_issue
          get_job
          get_job_log
          get_mcp_server_version
          get_merge_request
          get_merge_request_commits
          get_merge_request_conflicts
          get_merge_request_diffs
          get_merge_request_notes
          get_merge_request_pipelines
          get_pipeline
          get_pipeline_jobs
          get_project
          get_repository_file
          get_saved_view_work_items
          get_user
          get_vulnerability
          get_work_item
          get_work_item_notes
          get_work_item_types
          get_workitem_notes
          gitlab_merge_request_search
          gitlab_search
          list_all_merge_request_notes
          list_branches
          list_commits
          list_duo_sessions
          list_groups
          list_merge_request_diffs
          list_merge_requests
          list_pipelines
          list_project_members
          list_projects
          list_releases
          list_repository_tree
          list_tags
          list_vulnerabilities
          list_wiki_pages
          list_work_items
          search
          search_labels
          semantic_code_search
          semantic_search
        ]
      end

      # Only equal because default chat pre-approves everything it enables.
      let(:mcp_enabled_tools) { mcp_preapproved_tools }

      before do
        stub_feature_flags(duo_workflow_write_incremental_only: false)
      end

      it 'returns the websocket configuration with proper headers' do
        get_response

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.media_type).to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)
        expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
          'x-gitlab-oauth-token' => 'oauth_token',
          'authorization' => 'Bearer token',
          'x-gitlab-authentication-type' => 'oidc',
          'x-gitlab-enabled-feature-flags' => anything,
          'x-gitlab-instance-id' => anything,
          'x-gitlab-version' => Gitlab.version_info.to_s,
          'x-gitlab-unidirectional-streaming' => 'enabled',
          'x-gitlab-model-prompt-cache-enabled' => anything
        )

        expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-mcp-server-tools'].split(','))
          .to match_array(mcp_enabled_tools)

        expect(json_response['DuoWorkflow']['Service']['Secure']).to be(true)

        # For default chat (no catalog agent), Tools key is omitted so all MCP tools are available
        mcp_servers = json_response['DuoWorkflow']['McpServers']
        expect(mcp_servers['gitlab']['Headers']).to eq({ "Authorization" => "Bearer oauth_token" })
        expect(mcp_servers['gitlab']).not_to have_key('Tools')
        expect(mcp_servers['gitlab']['PreApprovedTools']).to match_array(mcp_preapproved_tools)

        expect(json_response['DuoWorkflow']['ServerCapabilities'])
          .to match_array(%w[job_trace_pagination tool_call_approval_source incremental_checkpoints])
      end

      it_behaves_like 'authorizing granular token permissions', :read_duo_workflow_websocket do
        let(:boundary_object) { :user }
        let(:request) do
          get api(path, personal_access_token: pat), headers: workhorse_headers,
            params: { workflow_definition: 'chat' }
        end
      end

      context 'when organization is assigned' do
        before do
          allow(Current).to receive(:organization_assigned).and_return(true)
        end

        it 'includes organization_id in ws service headers' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers'])
            .to include('x-gitlab-organization-id' => current_organization.id.to_s)
        end
      end

      context 'when organization is not assigned' do
        before do
          allow(Current).to receive(:organization_assigned).and_return(false)
        end

        it 'does not include x-gitlab-organization-id in ws service headers' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers'])
            .not_to have_key('x-gitlab-organization-id')
        end
      end

      context 'when GitLab MCP server tool governance is active' do
        let(:mcp_tools) do
          instance_double(
            ::Ai::ToolRules::GovernedMcpTools,
            empty?: false,
            rulable_names: ['search']
          )
        end

        def expect_claim(description)
          expect(::CloudConnector::Tokens).to receive(:get).with(
            hash_including(
              extra_claims: hash_including(
                tool_access_policies: satisfy(description) { |json| yield(::Gitlab::Json.parse(json)) }
              )
            )
          ).and_return('token')
        end

        before do
          allow(mcp_tools).to receive(:spellings_for).and_return([])
          allow(mcp_tools).to receive(:spellings_for).with('search').and_return(['gitlab_search'])
          # A catalog read tool the MCP server also serves, so resolution emits the
          # prefixed spelling on its own and can collide with the static list.
          allow(mcp_tools).to receive(:spellings_for)
            .with('get_merge_request').and_return(['gitlab_get_merge_request'])
          allow(::Ai::ToolRules::GovernedMcpTools).to receive(:for).and_return(mcp_tools)
        end

        it 'withdraws a denied MCP tool from the allow list the static append also feeds' do
          create(:ai_tool_rule, namespace: group, tool_name: 'search', web_access: :deny)

          expect_claim('denies gitlab_search and does not allow it') do |policies|
            policies['deny'].include?('gitlab_search') && policies['allow'].exclude?('gitlab_search')
          end

          get_response

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'keeps an asked MCP tool out of the allow list' do
          create(:ai_tool_rule, namespace: group, tool_name: 'search', web_access: :ask)

          expect_claim('asks for gitlab_search without allowing it') do |policies|
            policies['ask'].include?('gitlab_search') && policies['allow'].exclude?('gitlab_search')
          end

          get_response

          expect(response).to have_gitlab_http_status(:ok)
        end

        context 'without any rule' do
          it 'denies nothing and leaves the allow list intact' do
            expect_claim('has an empty deny list') { |policies| policies['deny'].empty? }

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end

          # Stubbing the static list keeps the duplicate reachable regardless of whether
          # this request would otherwise enable MCP.
          it 'names each allowed tool once' do
            allow_next_instance_of(::Ai::DuoWorkflows::McpConfigService) do |service|
              allow(service).to receive(:preapproved_tool_names)
                .and_return(%w[gitlab_get_merge_request])
            end

            expect_claim('allows gitlab_get_merge_request exactly once') do |policies|
              policies['allow'].count('gitlab_get_merge_request') == 1
            end

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when the namespace has a governance rule' do
        before do
          create(:ai_tool_rule, namespace: group, tool_name: 'create_issue', web_access: :allow)
        end

        it 'passes tool_access_policies from governance resolution to the cloud connector token' do
          expect(::CloudConnector::Tokens).to receive(:get).with(
            hash_including(
              extra_claims: hash_including(
                tool_access_policies: satisfy('allows create_work_item with an empty deny list') { |json|
                  policies = ::Gitlab::Json.parse(json)
                  policies['allow'].include?('create_work_item') && policies['deny'].empty?
                }
              )
            )
          ).and_return('token')

          get_response

          expect(response).to have_gitlab_http_status(:ok)
        end

        context 'when a tool is set to ask' do
          before do
            create(:ai_tool_rule, namespace: group, tool_name: 'run_command', web_access: :ask)
          end

          it 'passes the asked tool in the ask list' do
            expect(::CloudConnector::Tokens).to receive(:get).with(
              hash_including(
                extra_claims: hash_including(
                  tool_access_policies: satisfy('asks for run_command') { |json|
                    ::Gitlab::Json.parse(json)['ask'].include?('run_command')
                  }
                )
              )
            ).and_return('token')

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end
        end

        context 'when an asked tool is also pre-approved via MCP' do
          before do
            create(:ai_tool_rule, namespace: group, tool_name: 'gitlab_api_get', web_access: :ask)

            allow_next_instance_of(::Ai::DuoWorkflows::McpConfigService) do |service|
              allow(service).to receive(:preapproved_tool_names).and_return(['gitlab_api_get'])
            end
          end

          it 'excludes the asked tool from allow even though MCP would otherwise pre-approve it' do
            expect(::CloudConnector::Tokens).to receive(:get).with(
              hash_including(
                extra_claims: hash_including(
                  tool_access_policies: satisfy('asks for, but does not allow, gitlab_api_get') { |json|
                    policies = ::Gitlab::Json.parse(json)
                    policies['ask'].include?('gitlab_api_get') && policies['allow'].exclude?('gitlab_api_get')
                  }
                )
              )
            ).and_return('token')

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when the workflow is an allowlisted background flow' do
        let(:background_workflow) do
          create(:duo_workflows_workflow, user: user, environment: :web, workflow_definition: 'developer/v1')
        end

        subject(:get_response) do
          get api(path, user), headers: workhorse_headers, params: { workflow_id: background_workflow.id }
        end

        def expect_tool_access_policies(description)
          expect(::CloudConnector::Tokens).to receive(:get).with(
            hash_including(
              extra_claims: hash_including(
                tool_access_policies: satisfy(description) { |json| yield(::Gitlab::Json.parse(json)) }
              )
            )
          ).and_return('token')
        end

        it 'enforces a background-only deny' do
          create(:ai_tool_rule, namespace: group, tool_name: 'list_issues', background_access: :deny)
          expect_tool_access_policies('denies list_issues') { |policies| policies['deny'].include?('list_issues') }

          get_response

          expect(response).to have_gitlab_http_status(:ok)
        end

        context 'when the background-governance flag is disabled' do
          before do
            stub_feature_flags(duo_workflow_background_tool_governance: false)
          end

          it 'resolves the web surface, ignoring the background-only deny' do
            create(:ai_tool_rule, namespace: group, tool_name: 'list_issues', background_access: :deny)
            expect_tool_access_policies('does not deny list_issues') do |policies|
              policies['deny'].exclude?('list_issues')
            end

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when the workflow runs on a local surface' do
        let(:local_workflow) { create(:duo_workflows_workflow, user: user, environment: :ide) }

        subject(:get_response) do
          get api(path, user), headers: workhorse_headers, params: { workflow_id: local_workflow.id }
        end

        before do
          create(:ai_tool_rule, namespace: group, tool_name: 'run_command', web_access: :ask, local_access: :allow)
        end

        def expect_tool_access_policies(description)
          expect(::CloudConnector::Tokens).to receive(:get).with(
            hash_including(
              extra_claims: hash_including(
                tool_access_policies: satisfy(description) { |json| yield(::Gitlab::Json.parse(json)) }
              )
            )
          ).and_return('token')
        end

        it "resolves rules against the workflow's stored environment" do
          expect_tool_access_policies('allows run_command') do |policies|
            policies['allow'].include?('run_command')
          end

          get_response

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'resolves web rules when no workflow is given' do
          expect_tool_access_policies('does not allow run_command') do |policies|
            policies['allow'].exclude?('run_command')
          end

          get api(path, user), headers: workhorse_headers, params: { workflow_definition: 'chat' }

          expect(response).to have_gitlab_http_status(:ok)
        end

        context 'when the local-governance flag is disabled' do
          before do
            stub_feature_flags(duo_workflow_local_tool_governance: false)
          end

          it 'sends no policies at all rather than falling back to web rules' do
            # An ungoverned surface must not collapse to :web. Doing so governs an IDE
            # session against web_access rules while local governance is deliberately off.
            expect_tool_access_policies('is empty in every direction') do |policies|
              policies.values_at('allow', 'ask', 'deny').all?(&:empty?)
            end

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end

          it 'does not leak a web-only deny into the session' do
            create(:ai_tool_rule, namespace: group, tool_name: 'list_issues', web_access: :deny)

            expect_tool_access_policies('does not deny list_issues') do |policies|
              policies['deny'].exclude?('list_issues')
            end

            get_response

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when knowledge_graph feature flag is enabled' do
        let(:orbit_tools) { ::Ai::DuoWorkflows::McpConfigService::ORBIT_PREAPPROVED_TOOLS }

        before do
          stub_feature_flags(knowledge_graph: user, orbit_user_preference: false)
          stub_config(knowledge_graph: { 'enabled' => true })
        end

        it 'includes orbit MCP server in the DWS config alongside gitlab' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)

          mcp_servers = json_response['DuoWorkflow']['McpServers']

          expect(mcp_servers).to have_key('orbit')
          expect(mcp_servers['orbit']['Headers']).to eq({ "Authorization" => "Bearer oauth_token" })
          expect(mcp_servers['orbit']).not_to have_key('Tools')
          expect(mcp_servers['orbit']['PreApprovedTools']).to match_array(orbit_tools)

          expect(mcp_servers).to have_key('gitlab')
        end

        it 'includes prefixed orbit MCP pre-approved tools in the tool_access_policies allow list' do
          prefixed_orbit_tools = orbit_tools.map { |tool| "orbit_#{tool}" }

          expect(::CloudConnector::Tokens).to receive(:get).with(
            hash_including(
              extra_claims: hash_including(
                tool_access_policies: satisfy('allows the prefixed orbit MCP tools') { |json|
                  (prefixed_orbit_tools - ::Gitlab::Json.parse(json)['allow']).empty?
                }
              )
            )
          ).and_return('token')

          get_response

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when duo_agentic_chat_prefer_mcp_tools feature flag is enabled for root namespace' do
        before do
          stub_feature_flags(duo_agentic_chat_prefer_mcp_tools: group)
        end

        it 'includes duo_agentic_chat_prefer_mcp_tools in x-gitlab-enabled-feature-flags header' do
          get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-feature-flags'])
            .to include('duo_agentic_chat_prefer_mcp_tools')
        end
      end

      context 'when duo_agentic_chat_prefer_mcp_tools feature flag is disabled for root namespace' do
        before do
          stub_feature_flags(duo_agentic_chat_prefer_mcp_tools: false)
        end

        it 'does not include duo_agentic_chat_prefer_mcp_tools in x-gitlab-enabled-feature-flags header' do
          get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-feature-flags'])
            .not_to include('duo_agentic_chat_prefer_mcp_tools')
        end
      end

      context 'when software_development_flow_registry feature flag is enabled for user' do
        before do
          stub_feature_flags(software_development_flow_registry: user)
        end

        it 'includes software_development_flow_registry in x-gitlab-enabled-feature-flags header' do
          get api(path, user), headers: workhorse_headers

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-feature-flags'])
            .to include('software_development_flow_registry')
        end
      end

      context 'when software_development_flow_registry feature flag is disabled' do
        before do
          stub_feature_flags(software_development_flow_registry: false)
        end

        it 'does not include software_development_flow_registry in x-gitlab-enabled-feature-flags header' do
          get api(path, user), headers: workhorse_headers

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-feature-flags'])
            .not_to include('software_development_flow_registry')
        end
      end

      # Intelligent model routing is being trialled on the Duo Developer flow only, so
      # the flag has to reach that flow and no other. The exclusion cases also assert on
      # a flag push_feature_flags always sends, so a passing negative means the flag was
      # really left out rather than the header never having been populated.
      describe 'pushing duo_developer_model_routing' do
        let(:control_flag) { 'software_development_flow_registry' }
        let(:feature_setting_name) { nil }

        let(:request_headers) do
          if feature_setting_name
            workhorse_headers.merge('X-Gitlab-Agent-Platform-Feature-Setting-Name' => feature_setting_name)
          else
            workhorse_headers
          end
        end

        # The header is a single comma-joined string, so splitting it matches whole flag
        # names rather than substrings of longer ones.
        subject(:pushed_flags) do
          get api(path, user), headers: request_headers, params: { root_namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)

          json_response.dig('DuoWorkflow', 'Service', 'Headers', 'x-gitlab-enabled-feature-flags').to_s.split(',')
        end

        before do
          stub_feature_flags(control_flag.to_sym => true)
        end

        context 'when the flag is enabled for the user' do
          before do
            stub_feature_flags(duo_developer_model_routing: user)
          end

          context 'when the session is for the duo_developer flow' do
            let(:feature_setting_name) { 'duo_developer' }

            it 'pushes the flag' do
              expect(pushed_flags).to include('duo_developer_model_routing')
            end
          end

          # Sending no feature header at all, which :ws resolves to agentic chat.
          context 'when the session is for agentic chat' do
            it 'does not push the flag' do
              expect(pushed_flags).to include(control_flag)
              expect(pushed_flags).not_to include('duo_developer_model_routing')
            end
          end

          context 'when the session is for another flow' do
            let(:feature_setting_name) { 'duo_agent_platform' }

            it 'does not push the flag' do
              expect(pushed_flags).to include(control_flag)
              expect(pushed_flags).not_to include('duo_developer_model_routing')
            end
          end
        end

        context 'when the flag is disabled' do
          let(:feature_setting_name) { 'duo_developer' }

          before do
            stub_feature_flags(duo_developer_model_routing: false)
          end

          it 'does not push the flag' do
            expect(pushed_flags).to include(control_flag)
            expect(pushed_flags).not_to include('duo_developer_model_routing')
          end
        end
      end

      context 'when knowledge_graph feature flag is disabled' do
        before do
          stub_feature_flags(knowledge_graph: false)
        end

        it 'does not include orbit MCP server' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)

          mcp_servers = json_response['DuoWorkflow']['McpServers']
          expect(mcp_servers).not_to have_key('orbit')
          expect(mcp_servers).to have_key('gitlab')
        end
      end

      context 'when the request token is already scoped for AI workflows' do
        let_it_be(:ai_workflow_scopes) do
          ::Gitlab::Auth::AI_WORKFLOW_SCOPES + [::Gitlab::Auth::MCP_SCOPE, :"user:#{user.id}"]
        end

        let_it_be(:already_scoped_token) do
          create(:oauth_access_token, user: user, scopes: ai_workflow_scopes)
        end

        before do
          # Reset the composite identity stub so already_scoped_for_ai_workflows? uses real behavior
          allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor).and_call_original
        end

        it 'uses the plaintext bearer token from the request, not the hashed DB value' do
          get api(path, oauth_access_token: already_scoped_token), headers: workhorse_headers

          expect(response).to have_gitlab_http_status(:ok)

          oauth_token_in_response = json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-oauth-token']

          # The token in the response must equal the plaintext bearer token that was
          # sent in the request, so that the Duo Workflow service can use it.
          expect(oauth_token_in_response).to eq(already_scoped_token.plaintext_token)

          # Guard: the hashed DB value must differ from the plaintext, otherwise this
          # test would not catch the bug.
          expect(already_scoped_token.token).not_to eq(already_scoped_token.plaintext_token)
        end
      end

      context 'for ServerCapabilities' do
        context 'when advanced search is enabled for the project' do
          before do
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
              .with(scope: project).and_return(true)
          end

          it 'returns advanced_search capability' do
            get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['ServerCapabilities']).to match_array(%w[job_trace_pagination
              advanced_search tool_call_approval_source incremental_checkpoints])
          end
        end

        context 'when advanced search is disabled' do
          before do
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?).and_return(false)
          end

          it 'returns only default Rails capabilities' do
            get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['ServerCapabilities']).to match_array(%w[job_trace_pagination
              tool_call_approval_source incremental_checkpoints])
          end
        end

        context 'when namespace_id is provided instead of project_id' do
          before do
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
                                                  .with(scope: group).and_return(true)
          end

          it 'checks advanced search for the namespace' do
            get api(path, user), headers: workhorse_headers, params: { namespace_id: group.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['ServerCapabilities']).to match_array(%w[job_trace_pagination
              advanced_search tool_call_approval_source incremental_checkpoints])
          end
        end

        context 'when root_namespace_id is provided' do
          before do
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
                                                  .with(scope: group).and_return(true)
          end

          it 'checks advanced search for the root namespace' do
            get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['ServerCapabilities']).to match_array(%w[job_trace_pagination
              advanced_search tool_call_approval_source incremental_checkpoints])
          end
        end

        context 'when namespace is provided via header' do
          before do
            allow(::Gitlab::CurrentSettings).to receive(:search_using_elasticsearch?)
                                                  .with(scope: group).and_return(true)
          end

          it 'checks advanced search for the namespace from header' do
            get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => group.id)

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['ServerCapabilities']).to match_array(%w[job_trace_pagination
              advanced_search tool_call_approval_source incremental_checkpoints])
          end
        end

        context 'when neither advanced_search nor DWS capabilities are present' do
          it 'returns only default Rails capabilities' do
            get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['ServerCapabilities']).to match_array(%w[job_trace_pagination
              tool_call_approval_source incremental_checkpoints])
          end
        end
      end

      context 'when self-hosted DAP billing is enabled for the feature' do
        before do
          allow(Ai::SelfHostedDapBilling).to receive(:should_bill?).and_return(true)
          allow(::CloudConnector::Tokens).to receive(:cloud_connector_token).and_return('cloud_connector_token')
        end

        it 'populates CloudServiceForSelfHosted with Cloud Connector values' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)

          cloud_service = json_response['DuoWorkflow']['CloudServiceForSelfHosted']
          expect(cloud_service['URI']).to eq(Gitlab::DuoWorkflow::Client.cloud_connected_url(user: user))
          expect(cloud_service['Headers']).to be_present
          expect(cloud_service['Headers']).to include('authorization' => "Bearer cloud_connector_token")
          expect(cloud_service['Secure']).to be(true)
        end

        it 'includes project and client type context in CloudServiceForSelfHosted headers' do
          get api(path, user),
            headers: workhorse_headers,
            params: { workflow_definition: 'chat', project_id: project.id, client_type: 'web' }

          expect(response).to have_gitlab_http_status(:ok)

          cloud_service = json_response['DuoWorkflow']['CloudServiceForSelfHosted']
          expect(cloud_service['Headers']).to include(
            'x-gitlab-project-id' => project.id.to_s,
            'x-gitlab-client-type' => 'web'
          )
        end

        context 'when the workflow is triggered by verification' do
          let_it_be(:workflow) do
            create(:duo_workflows_workflow, user: user, workflow_definition: 'chat', trigger_source: :verification)
          end

          subject(:get_response) do
            get api(path, user), headers: workhorse_headers,
              params: { workflow_definition: 'chat', workflow_id: workflow.id }
          end

          it 'omits CloudServiceForSelfHosted config' do
            get_response

            expect(response).to have_gitlab_http_status(:ok)

            cloud_service = json_response['DuoWorkflow']['CloudServiceForSelfHosted']
            expect(cloud_service).to be_nil
          end
        end
      end

      context 'when self-hosted DAP billing is disabled for the feature' do
        before do
          allow(Ai::SelfHostedDapBilling).to receive(:should_bill?).and_return(false)
        end

        it 'omits CloudServiceForSelfHosted config' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)

          cloud_service = json_response['DuoWorkflow']['CloudServiceForSelfHosted']
          expect(cloud_service).to be_nil
        end
      end

      context 'for x-gitlab-extended-logging header' do
        context 'when enable_extended_logging? returns true' do
          before do
            allow(Gitlab::DuoWorkflow::Client).to receive(:enable_extended_logging?).and_return(true)
          end

          it 'sets x-gitlab-extended-logging to "true"' do
            get_response

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-extended-logging']).to eq('true')
          end
        end

        context 'when enable_extended_logging? returns false' do
          before do
            allow(Gitlab::DuoWorkflow::Client).to receive(:enable_extended_logging?).and_return(false)
          end

          it 'sets x-gitlab-extended-logging to "false"' do
            get_response

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-extended-logging']).to eq('false')
          end
        end

        it 'passes the most specific namespace to enable_extended_logging?' do
          expect(Gitlab::DuoWorkflow::Client).to receive(:enable_extended_logging?)
            .with(user, namespace: group)
            .and_return(false)

          get api(path, user), headers: workhorse_headers,
            params: { workflow_definition: 'chat', namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when workflow_definition is for agentic chat' do
        it 'includes MCP server configuration' do
          get api(path, user), headers: workhorse_headers, params: { workflow_definition: 'chat' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['McpServers']).to be_present
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-mcp-server-tools']).to be_present
        end
      end

      context 'when workflow_definition is for a foundational agent' do
        it 'does not include MCP server configuration' do
          get api(path, user), headers: workhorse_headers, params: { workflow_definition: 'software_development' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['McpServers']).to be_empty
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-enabled-mcp-server-tools']).to eq('')
        end
      end

      context 'when ai_catalog_item_version_id is provided' do
        let_it_be(:catalog_item_version) do
          create(:ai_catalog_item_version, definition: {
            'system_prompt' => 'You are a helpful assistant.',
            'tools' => [17, 6],
            'mcp_tools' => %w[search save_note]
          })
        end

        it 'resolves agent tool IDs and restricts MCP tools accordingly' do
          get api(path, user), headers: workhorse_headers, params: {
            workflow_definition: 'chat',
            ai_catalog_item_version_id: catalog_item_version.id
          }

          expect(response).to have_gitlab_http_status(:ok)

          mcp_servers = json_response['DuoWorkflow']['McpServers']
          expect(mcp_servers['gitlab']).to have_key('Tools')
          expect(mcp_servers['gitlab']['Tools']).to be_an(Array)
          expect(mcp_servers['gitlab']['PreApprovedTools']).to match_array(%w[get_issue search])
          expect(mcp_servers['gitlab']['PreApprovedTools']).to all(be_in(mcp_servers['gitlab']['Tools']))
        end

        context 'when mcp_tools selects a pre-consolidation alias tool name' do
          let_it_be(:alias_catalog_item_version) do
            create(:ai_catalog_item_version, definition: {
              'system_prompt' => 'You are a helpful assistant.',
              'tools' => [],
              'mcp_tools' => %w[create_workitem_note]
            })
          end

          it 'resolves the alias to save_note, the name the MCP server advertises' do
            get api(path, user), headers: workhorse_headers, params: {
              workflow_definition: 'chat',
              ai_catalog_item_version_id: alias_catalog_item_version.id
            }

            expect(response).to have_gitlab_http_status(:ok)

            mcp_servers = json_response['DuoWorkflow']['McpServers']
            expect(mcp_servers['gitlab']['Tools']).to contain_exactly('save_note')
          end
        end

        context 'when the version does not exist' do
          it 'falls back to default tool behavior' do
            get api(path, user), headers: workhorse_headers, params: {
              workflow_definition: 'chat',
              ai_catalog_item_version_id: non_existing_record_id
            }

            expect(response).to have_gitlab_http_status(:ok)

            # Falls back to default chat behavior (no Tools key)
            mcp_servers = json_response['DuoWorkflow']['McpServers']
            expect(mcp_servers['gitlab']).not_to have_key('Tools')
            expect(mcp_servers['gitlab']['PreApprovedTools']).to match_array(mcp_preapproved_tools)
          end
        end
      end

      context 'for MCP server block enforcement' do
        it 'builds the MCP config with the request namespace' do
          expect(::Ai::DuoWorkflows::McpConfigService).to receive(:new)
            .with(user, anything, hash_including(namespace: group))
            .and_call_original

          get api(path, user), headers: workhorse_headers, params: { workflow_definition: 'chat' }

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'prefers the project namespace when a project is in scope' do
          expect(::Ai::DuoWorkflows::McpConfigService).to receive(:new)
            .with(user, anything, hash_including(namespace: project.project_namespace))
            .and_call_original

          get api(path, user), headers: workhorse_headers,
            params: { workflow_definition: 'chat', project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'anchors enforcement to the root namespace when the header points at a foreign hierarchy' do
          foreign_group = create(:group, developers: user)

          expect(::Ai::DuoWorkflows::McpConfigService).to receive(:new)
            .with(user, anything, hash_including(namespace: group))
            .and_call_original

          get api(path, user),
            headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => foreign_group.id.to_s),
            params: { workflow_definition: 'chat', root_namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'keeps a header namespace that is inside the root hierarchy' do
          subgroup = create(:group, parent: group)

          expect(::Ai::DuoWorkflows::McpConfigService).to receive(:new)
            .with(user, anything, hash_including(namespace: subgroup))
            .and_call_original

          get api(path, user),
            headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => subgroup.id.to_s),
            params: { workflow_definition: 'chat', root_namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when workflow_id is provided for provider stickiness' do
        let(:stored_metadata) { '{"provider":"anthropic","name":"claude_3"}' }
        let(:existing_workflow) do
          create(:duo_workflows_workflow, user: user, project: project,
            model_metadata_json: stored_metadata)
        end

        context 'when duo_workflow_provider_stickiness feature flag is enabled' do
          before do
            stub_feature_flags(duo_workflow_provider_stickiness: group)
          end

          it 'reuses the stored model metadata from the workflow' do
            get api(path, user), headers: workhorse_headers,
              params: { workflow_id: existing_workflow.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
              'x-gitlab-agent-platform-model-metadata' => stored_metadata
            )
          end

          context 'when the workflow has no stored model metadata' do
            let(:existing_workflow) do
              create(:duo_workflows_workflow, user: user, project: project,
                model_metadata_json: nil)
            end

            it 'falls back to the model metadata service' do
              get api(path, user), headers: workhorse_headers,
                params: { workflow_id: existing_workflow.id }

              expect(response).to have_gitlab_http_status(:ok)
            end
          end

          context 'when workflow_id does not belong to the current user' do
            let(:other_user) { create(:user, maintainer_of: project) }
            let(:other_workflow) do
              create(:duo_workflows_workflow, user: other_user, project: project,
                model_metadata_json: stored_metadata)
            end

            it 'returns not found' do
              get api(path, user), headers: workhorse_headers,
                params: { workflow_id: other_workflow.id }

              expect(response).to have_gitlab_http_status(:not_found)
            end
          end
        end

        context 'when duo_workflow_provider_stickiness feature flag is disabled' do
          before do
            stub_feature_flags(duo_workflow_provider_stickiness: false)
          end

          it 'does not use stored model metadata' do
            get api(path, user), headers: workhorse_headers,
              params: { workflow_id: existing_workflow.id }

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-agent-platform-model-metadata'])
              .not_to eq(stored_metadata)
          end
        end
      end

      it_behaves_like 'ServiceURI has the right value', false

      context 'when current_user is a composite identity user' do
        let_it_be(:service_account) { create(:service_account, composite_identity_enforced: true) }
        let_it_be(:scopes) { ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{user.id}"] }
        let_it_be(:oauth_access_token) do
          create(:oauth_access_token, resource_owner: service_account, scopes: scopes)
        end

        it 'generates a token using the correct service account' do
          expect(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).with(
            a_hash_including(service_account: have_attributes(id: service_account.id))
          ).and_call_original

          get api(path, oauth_access_token:), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
        end

        context 'and namespace is specified' do
          let_it_be(:group) { create(:group, :private) }
          let_it_be_with_refind(:project) { create(:project, :repository, group: group) }

          it 'is successful' do
            project.add_developer(service_account)
            group.add_developer(user)

            get api(path, oauth_access_token:), headers: workhorse_headers,
              params: { project_id: project.id, namespace_id: group.id, root_namespace_id: group.root_ancestor.id }

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when project_id parameter is provided' do
        it 'includes x-gitlab-project-id header' do
          get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-project-id' => project.id.to_s
          )
        end

        it 'sets x-gitlab-project-id header to nil when project_id is blank' do
          get api(path, user), headers: workhorse_headers, params: { project_id: '' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-project-id']).to be_nil
        end
      end

      context 'when X-Gitlab-Language-Server-Version header is provided' do
        it 'includes x-gitlab-language-server-version header' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Language-Server-Version': "8.22.0"),
            params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-language-server-version' => "8.22.0"
          )
        end

        it 'does not include x-gitlab-language-server-version header when header is not provided' do
          get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-language-server-version']).to be_nil
        end
      end

      context 'for X-Gitlab-Client-Type header' do
        it 'sends x-gitlab-client-type gRPC header when http request have X-Gitlab-Client-Type header' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Client-Type': "node-websocket"),
            params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-client-type' => "node-websocket"
          )
        end

        it 'sends x-gitlab-client-type gRPC header when http request have client_type param' do
          get api(path, user), headers: workhorse_headers,
            params: { project_id: project.id, client_type: 'browser' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-client-type' => "browser"
          )
        end

        it 'does not include x-gitlab-client-type header when neither header nor param is provided' do
          get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-client-type']).to be_nil
        end
      end

      context 'for X-Gitlab-Client-Name header' do
        it 'includes x-gitlab-client-name in DWS headers when header is provided' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Client-Name': 'Duo CLI'),
            params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-client-name' => 'Duo CLI'
          )
        end

        it 'does not include x-gitlab-client-name header when header is not provided' do
          get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-client-name']).to be_nil
        end
      end

      context 'for X-Gitlab-Client-Version header' do
        it 'includes x-gitlab-client-version in DWS headers when header is provided' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Client-Version': '8.70.0'),
            params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-client-version' => '8.70.0'
          )
        end

        it 'does not include x-gitlab-client-version header when header is not provided' do
          get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-client-version']).to be_nil
        end
      end

      context 'for X-Gitlab-Tracking-Context header' do
        let(:tracking_context) { '{"distribution":"npm","execution_environment":"CI"}' }

        it 'includes x-gitlab-tracking-context in DWS headers when header is provided' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Tracking-Context': tracking_context),
            params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-tracking-context' => tracking_context
          )
        end

        it 'does not include x-gitlab-tracking-context header when header is not provided' do
          get api(path, user), headers: workhorse_headers, params: { project_id: project.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-tracking-context']).to be_nil
        end
      end

      context 'for LockConcurrentFlow' do
        using RSpec::Parameterized::TableSyntax

        where(:client_type) do
          [nil, 'browser', 'node-websocket']
        end

        with_them do
          it 'enables locking regardless of the client type' do
            get api(path, user), headers: workhorse_headers,
              params: { project_id: project.id, client_type: client_type }.compact

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['LockConcurrentFlow']).to be(true)
          end
        end
      end

      context 'for TimeoutHTTPRequests' do
        context 'when timeout_dap_http_requests_in_workhorse FF is enabled' do
          before do
            stub_feature_flags(timeout_dap_http_requests_in_workhorse: true)
          end

          it 'enables HTTP request timeouts' do
            get api(path, user), headers: workhorse_headers,
              params: { project_id: project.id }.compact

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['TimeoutHTTPRequests']).to be(true)
          end
        end

        context 'when timeout_dap_http_requests_in_workhorse FF is disabled' do
          before do
            stub_feature_flags(timeout_dap_http_requests_in_workhorse: false)
          end

          it 'sets TimeoutHTTPRequests to false' do
            get api(path, user), headers: workhorse_headers,
              params: { project_id: project.id }.compact

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['TimeoutHTTPRequests']).to be(false)
          end
        end
      end

      context 'when namespace_id parameter is provided' do
        it 'includes x-gitlab-namespace-id header' do
          get api(path, user), headers: workhorse_headers, params: { namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-namespace-id' => group.id.to_s
          )
        end

        it 'falls back to X-Gitlab-Namespace-Id header when namespace_id is blank' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => group.id),
            params: { namespace_id: '' }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-namespace-id' => group.id.to_s,
            'x-gitlab-root-namespace-id' => group.id.to_s
          )
        end
      end

      context 'when root_namespace_id parameter is provided' do
        it 'includes x-gitlab-root-namespace-id header and sets namespace-id to root' do
          get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-root-namespace-id' => group.id.to_s,
            'x-gitlab-namespace-id' => group.id.to_s
          )
        end

        it 'uses default value when namespace is not found' do
          get api(path, user), headers: workhorse_headers, params: { root_namespace_id: 99999 }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-root-namespace-id' => group.id.to_s,
            'x-gitlab-namespace-id' => group.id.to_s
          )
        end
      end

      context 'when both project_id and namespace_id parameters are provided' do
        it 'includes both x-gitlab-project-id and x-gitlab-namespace-id headers' do
          get api(path, user), headers: workhorse_headers, params: {
            project_id: project.id,
            namespace_id: group.id
          }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-project-id' => project.id.to_s,
            'x-gitlab-namespace-id' => group.id.to_s
          )
        end
      end

      context 'when namespace is provided via X-Gitlab-Namespace-Id header' do
        it 'includes x-gitlab-namespace-id header in response' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => group.id)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-namespace-id' => group.id.to_s
          )
        end
      end

      context 'when precedence of namespace parameters is tested' do
        let_it_be(:child_group) { create(:group, parent: group) }
        let_it_be(:auth_response) do
          Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [group.id, child_group.id])
        end

        it 'sets both root and namespace headers, with namespace_id taking precedence for x-gitlab-namespace-id' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => child_group.id), params: {
            root_namespace_id: group.id,
            namespace_id: child_group.id
          }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-root-namespace-id' => group.id.to_s,
            'x-gitlab-namespace-id' => child_group.id.to_s
          )
        end

        it 'uses namespace_id parameter over X-Gitlab-Namespace-Id header when root_namespace_id is not provided' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => group.id), params: {
            namespace_id: child_group.id
          }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-namespace-id' => child_group.id.to_s,
            'x-gitlab-root-namespace-id' => child_group.root_ancestor.id.to_s
          )
        end

        it 'falls back to X-Gitlab-Namespace-Id header when no namespace params are provided' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => group.id)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-namespace-id' => group.id.to_s,
            'x-gitlab-root-namespace-id' => group.id.to_s
          )
        end

        it 'uses root_namespace_id for x-gitlab-namespace-id when only root_namespace_id is provided' do
          get api(path, user), headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => child_group.id), params: {
            root_namespace_id: group.id
          }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
            'x-gitlab-root-namespace-id' => group.id.to_s,
            'x-gitlab-namespace-id' => group.id.to_s
          )
        end
      end

      # rubocop:disable RSpec/MultipleMemoizedHelpers -- Complex authorization test requires multiple groups, projects, and namespaces to validate security boundaries
      context 'with namespace authorization and context validation' do
        let_it_be(:other_group) { create(:group) }
        let_it_be(:other_project) { create(:project, :repository, group: other_group) }
        let_it_be(:unauthorized_group) { create(:group, :private) }
        let_it_be(:parent_group_2) { create(:group) }
        let_it_be(:child_group_2) { create(:group, parent: parent_group_2) }
        let_it_be(:nested_project_2) { create(:project, :repository, group: child_group_2) }
        let_it_be(:parent_group_3) { create(:group) }
        let_it_be(:child_group_3) { create(:group, parent: parent_group_3) }
        let_it_be(:premium_group) { create(:group) }
        let_it_be(:basic_project) { create(:project, :repository, group: group) }

        before_all do
          other_group.add_developer(user)
          parent_group_2.add_developer(user)
          parent_group_3.add_developer(user)
          premium_group.add_guest(user)
        end

        context 'when namespace authorization is enforced' do
          context 'when user has no access to the namespace' do
            it 'returns 404 when namespace is provided via root_namespace_id' do
              get api(path, user), headers: workhorse_headers, params: {
                root_namespace_id: unauthorized_group.id
              }

              expect(response).to have_gitlab_http_status(:not_found)
              expect(json_response['message']).to eq('404 Namespace Not Found')
            end

            it 'returns 404 when namespace is provided via namespace_id' do
              get api(path, user), headers: workhorse_headers, params: {
                namespace_id: unauthorized_group.id
              }

              expect(response).to have_gitlab_http_status(:not_found)
              expect(json_response['message']).to eq('404 Namespace Not Found')
            end

            it 'returns 404 when namespace is provided via header' do
              get api(path, user), headers: workhorse_headers.merge(
                'X-Gitlab-Namespace-Id' => unauthorized_group.id
              )

              expect(response).to have_gitlab_http_status(:not_found)
              expect(json_response['message']).to eq('404 Namespace Not Found')
            end
          end

          context 'when user has access to the namespace' do
            it 'succeeds when accessing authorized namespace' do
              get api(path, user), headers: workhorse_headers, params: {
                root_namespace_id: group.id
              }

              expect(response).to have_gitlab_http_status(:ok)
              expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
                'x-gitlab-root-namespace-id' => group.id.to_s
              )
            end
          end
        end

        context 'when context validation is required' do
          context 'with project context' do
            context 'when namespace does not match project context' do
              it 'returns 403 forbidden when using mismatched namespace via root_namespace_id' do
                get api(path, user), headers: workhorse_headers, params: {
                  project_id: project.id,
                  root_namespace_id: other_group.id
                }

                expect(response).to have_gitlab_http_status(:forbidden)
                expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
              end

              it 'returns 403 forbidden when using mismatched namespace via header' do
                get api(path, user), headers: workhorse_headers.merge(
                  'X-Gitlab-Namespace-Id' => other_group.id
                ), params: {
                  project_id: project.id
                }

                expect(response).to have_gitlab_http_status(:forbidden)
                expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
              end

              it 'returns 403 forbidden when namespace_id does not match project' do
                get api(path, user), headers: workhorse_headers, params: {
                  project_id: project.id,
                  namespace_id: other_group.id
                }

                expect(response).to have_gitlab_http_status(:forbidden)
                expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
              end
            end

            context 'when namespace matches project context' do
              it 'succeeds when namespace matches project root namespace' do
                get api(path, user), headers: workhorse_headers, params: {
                  project_id: project.id,
                  root_namespace_id: group.id
                }

                expect(response).to have_gitlab_http_status(:ok)
                expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
                  'x-gitlab-project-id' => project.id.to_s,
                  'x-gitlab-root-namespace-id' => group.id.to_s
                )
              end
            end

            context 'with nested groups and projects' do
              before do
                allow_any_instance_of(User).to receive(:allowed_to_use).and_return( # rubocop:disable RSpec/AnyInstanceOf -- overriding top-level mock
                  Ai::UserAuthorizable::Response.new(
                    allowed?: true,
                    namespace_ids: [group.id, other_group.id, parent_group_2.id, child_group_2.id]
                  )
                )
              end

              it 'succeeds when using child group namespace with nested project' do
                get api(path, user), headers: workhorse_headers, params: {
                  project_id: nested_project_2.id,
                  namespace_id: child_group_2.id
                }

                expect(response).to have_gitlab_http_status(:ok)
              end

              it 'succeeds when using root namespace with nested project' do
                get api(path, user), headers: workhorse_headers, params: {
                  project_id: nested_project_2.id,
                  root_namespace_id: parent_group_2.id
                }

                expect(response).to have_gitlab_http_status(:ok)
                expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
                  'x-gitlab-project-id' => nested_project_2.id.to_s,
                  'x-gitlab-root-namespace-id' => parent_group_2.id.to_s
                )
              end

              it 'returns 403 when using wrong root namespace with nested project' do
                get api(path, user), headers: workhorse_headers, params: {
                  project_id: nested_project_2.id,
                  root_namespace_id: other_group.id
                }

                expect(response).to have_gitlab_http_status(:forbidden)
                expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
              end
            end
          end

          context 'with namespace context (no project)' do
            context 'when namespace does not match workflow context' do
              it 'returns 403 forbidden when root namespace does not match namespace context' do
                get api(path, user), headers: workhorse_headers, params: {
                  namespace_id: group.id,
                  root_namespace_id: other_group.id
                }

                expect(response).to have_gitlab_http_status(:forbidden)
                expect(json_response['message']).to eq('403 Forbidden - Namespace does not match workflow context')
              end
            end

            context 'when namespace matches workflow context' do
              it 'succeeds when namespace matches' do
                get api(path, user), headers: workhorse_headers, params: {
                  namespace_id: group.id,
                  root_namespace_id: group.id
                }

                expect(response).to have_gitlab_http_status(:ok)
                expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
                  'x-gitlab-namespace-id' => group.id.to_s,
                  'x-gitlab-root-namespace-id' => group.id.to_s
                )
              end
            end

            context 'with nested groups' do
              before do
                allow_any_instance_of(User).to receive(:allowed_to_use).and_return( # rubocop:disable RSpec/AnyInstanceOf -- overriding top-level mock
                  Ai::UserAuthorizable::Response.new(
                    allowed?: true,
                    namespace_ids: [group.id, other_group.id, parent_group_3.id, child_group_3.id]
                  )
                )
              end

              it 'succeeds when namespace matches child group root ancestor' do
                get api(path, user), headers: workhorse_headers, params: {
                  namespace_id: child_group_3.id,
                  root_namespace_id: parent_group_3.id
                }

                expect(response).to have_gitlab_http_status(:ok)
                expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
                  'x-gitlab-namespace-id' => child_group_3.id.to_s,
                  'x-gitlab-root-namespace-id' => parent_group_3.id.to_s
                )
              end

              it 'returns 403 when root namespace does not match child group ancestor' do
                get api(path, user), headers: workhorse_headers, params: {
                  namespace_id: child_group_3.id,
                  root_namespace_id: other_group.id
                }

                expect(response).to have_gitlab_http_status(:forbidden)
                expect(json_response['message']).to eq('403 Forbidden - Namespace does not match workflow context')
              end
            end
          end
        end

        context 'when context validation is NOT required (no project or namespace params)' do
          it 'uses the governing namespace' do
            get api(path, user), headers: workhorse_headers

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response['DuoWorkflow']['Service']['Headers']).to include(
              'x-gitlab-namespace-id' => group.id.to_s,
              'x-gitlab-root-namespace-id' => group.id.to_s
            )
          end

          context 'when the user has no governing namespace' do
            include_context 'with user governing namespace' do
              let(:governing_namespace) { nil }
            end

            it 'returns an error response' do
              get api(path, user), headers: workhorse_headers

              expect(response).to have_gitlab_http_status(:forbidden)
              expect(json_response['message']).to include('Missing default GitLab Duo namespace user preference')
            end
          end
        end

        context 'with security edge cases' do
          context 'when attempting to escalate privileges' do
            it 'blocks attempt to use premium namespace with basic project' do
              get api(path, user), headers: workhorse_headers, params: {
                project_id: basic_project.id,
                root_namespace_id: premium_group.id
              }

              expect(response).to have_gitlab_http_status(:forbidden)
              expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
            end

            it 'blocks attempt to inject namespace via header with project context' do
              get api(path, user), headers: workhorse_headers.merge(
                'X-Gitlab-Namespace-Id' => premium_group.id
              ), params: {
                project_id: basic_project.id
              }

              expect(response).to have_gitlab_http_status(:forbidden)
              expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
            end
          end

          context 'with multiple conflicting namespace sources' do
            it 'validates against the effective namespace when namespace_id conflicts with header' do
              get api(path, user), headers: workhorse_headers.merge(
                'X-Gitlab-Namespace-Id' => group.id
              ), params: {
                project_id: project.id,
                namespace_id: other_group.id
              }

              expect(response).to have_gitlab_http_status(:forbidden)
              expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
            end

            it 'validates root_namespace_id against project context when both root and namespace_id provided' do
              get api(path, user), headers: workhorse_headers, params: {
                project_id: project.id,
                root_namespace_id: other_group.id,
                namespace_id: group.id
              }

              expect(response).to have_gitlab_http_status(:forbidden)
              expect(json_response['message']).to eq('403 Forbidden - Namespace does not match project context')
            end
          end
        end
      end
      # rubocop:enable RSpec/MultipleMemoizedHelpers

      context 'for self hosted duo agent platform' do
        let_it_be(:self_hosted_model) do
          create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
        end

        let_it_be_with_refind(:duo_agent_platform_setting) do
          create(:ai_feature_setting, :duo_agent_platform_agentic_chat, self_hosted_model: self_hosted_model)
        end

        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it 'includes model metadata headers in the response' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)

          headers = json_response['DuoWorkflow']['Service']['Headers']
          expect(headers).to include(
            'x-gitlab-oauth-token' => 'oauth_token',
            'x-gitlab-unidirectional-streaming' => 'enabled',
            'x-gitlab-agent-platform-model-metadata' => be_a(String)
          )

          metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
          expect(metadata).to include(
            'provider' => 'openai',
            'name' => 'claude_3',
            'identifier' => self_hosted_model.identifier,
            'api_key' => self_hosted_model.api_token,
            'endpoint' => self_hosted_model.endpoint
          )
        end

        it 'sets x-gitlab-self-hosted-dap-billing-enabled header to true when billing should occur' do
          allow(Ai::SelfHostedDapBilling).to receive(:should_bill?)
            .with(duo_agent_platform_setting).and_return(true)

          get_response

          expect(response).to have_gitlab_http_status(:ok)

          headers = json_response['DuoWorkflow']['Service']['Headers']
          expect(headers).to include(
            'x-gitlab-self-hosted-dap-billing-enabled' => 'true'
          )
        end

        it 'sets x-gitlab-self-hosted-dap-billing-enabled header to false when billing should not occur' do
          allow(Ai::SelfHostedDapBilling).to receive(:should_bill?)
            .with(duo_agent_platform_setting).and_return(false)

          get_response

          expect(response).to have_gitlab_http_status(:ok)

          headers = json_response['DuoWorkflow']['Service']['Headers']
          expect(headers).to include(
            'x-gitlab-self-hosted-dap-billing-enabled' => 'false'
          )
        end

        context 'when the workflow is triggered by verification' do
          let_it_be(:workflow) do
            create(:duo_workflows_workflow, user: user, workflow_definition: 'chat', trigger_source: :verification)
          end

          subject(:get_response) do
            get api(path, user), headers: workhorse_headers,
              params: { workflow_definition: 'chat', workflow_id: workflow.id }
          end

          before do
            allow(Ai::SelfHostedDapBilling).to receive(:should_bill?)
              .with(duo_agent_platform_setting).and_return(true)
          end

          it 'forces the billing header to false' do
            get_response

            expect(response).to have_gitlab_http_status(:ok)

            headers = json_response['DuoWorkflow']['Service']['Headers']
            expect(headers).to include('x-gitlab-self-hosted-dap-billing-enabled' => 'false')
          end
        end

        it 'creates ModelMetadata with the correct feature setting' do
          expect(::Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata).to receive(:new)
            .with(feature_setting: duo_agent_platform_setting)
            .and_call_original

          get api(path, user), headers: workhorse_headers
        end

        it_behaves_like 'ServiceURI has the right value', true

        context 'when feature setting is disabled' do
          subject(:get_response) do
            duo_agent_platform_setting.update!(provider: :disabled)

            get api(path, user), headers: workhorse_headers
          end

          it 'does not include model metadata headers when provider is disabled' do
            get_response

            expect(response).to have_gitlab_http_status(:ok)

            headers = json_response['DuoWorkflow']['Service']['Headers']
            expect(headers).to include(
              'x-gitlab-oauth-token' => 'oauth_token',
              'x-gitlab-unidirectional-streaming' => 'enabled'
            )
            expect(headers).not_to have_key('x-gitlab-agent-platform-model-metadata')
          end

          it_behaves_like 'ServiceURI has the right value', false
        end
      end

      context 'for model selection at instance level' do
        let_it_be(:instance_setting) do
          create(:instance_model_selection_feature_setting,
            feature: :duo_agent_platform_agentic_chat,
            offered_model_ref: 'claude-3-7-sonnet-20250219')
        end

        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it 'includes model metadata headers in the response' do
          get_response

          expect(response).to have_gitlab_http_status(:ok)

          headers = json_response['DuoWorkflow']['Service']['Headers']

          metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
          expect(metadata).to include(
            'provider' => 'gitlab',
            'feature_setting' => 'duo_agent_platform_agentic_chat',
            'identifier' => 'claude-3-7-sonnet-20250219'
          )
        end

        it_behaves_like 'ServiceURI has the right value', false
      end

      context 'for model selection at namespace level', :saas do
        include_context 'with model selections fetch definition service side-effect context'

        # CRITICAL FIX: Use a different variable name and add user access
        let_it_be(:model_selection_group) { create(:group) }

        before_all do
          model_selection_group.add_developer(user)
        end

        before do
          stub_saas_features(gitlab_com_subscriptions: true)

          stub_request(:get, fetch_service_endpoint_url)
            .to_return(
              status: 200,
              body: model_definitions_response,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it_behaves_like 'ServiceURI has the right value', false

        context 'when namespace params are provided' do
          context 'when a model selection setting exists' do
            let_it_be(:namespace_setting) do
              create(:ai_namespace_feature_setting,
                namespace: model_selection_group,
                feature: :duo_agent_platform_agentic_chat,
                offered_model_ref: 'claude_sonnet_3_7_20250219')
            end

            context 'when provided as param[:root_namespace_id]' do
              subject(:get_response) do
                get api(path, user), headers: workhorse_headers, params: { root_namespace_id: model_selection_group.id }
              end

              it 'includes model metadata headers' do
                get_response

                expect(response).to have_gitlab_http_status(:ok)

                headers = json_response['DuoWorkflow']['Service']['Headers']
                expect(headers).to have_key('x-gitlab-agent-platform-model-metadata')

                metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                expect(metadata).to include(
                  'provider' => 'gitlab',
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'identifier' => 'claude_sonnet_3_7_20250219'
                )
              end

              it_behaves_like 'ServiceURI has the right value', false

              context 'when user_selected_model_identifier is provided' do
                context 'when a valid user_selected_model_identifier is provided' do
                  let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

                  subject(:get_response) do
                    get api(path, user), headers: workhorse_headers, params: {
                      root_namespace_id: model_selection_group.id,
                      user_selected_model_identifier: user_selected_model_identifier
                    }
                  end

                  it 'continues to use the namespace-level model selection' do
                    get_response

                    expect(response).to have_gitlab_http_status(:ok)

                    headers = json_response['DuoWorkflow']['Service']['Headers']
                    metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                    expect(metadata).to include(
                      'provider' => 'gitlab',
                      'feature_setting' => 'duo_agent_platform_agentic_chat',
                      'identifier' => 'claude_sonnet_3_7_20250219'
                    )
                  end

                  it_behaves_like 'ServiceURI has the right value', false
                end
              end
            end

            context 'when provided as header[X-Gitlab-Namespace-Id]' do
              subject(:get_response) do
                get api(path, user),
                  headers: workhorse_headers.merge('X-Gitlab-Namespace-Id' => model_selection_group.id)
              end

              it 'includes model metadata headers' do
                get_response

                expect(response).to have_gitlab_http_status(:ok)

                headers = json_response['DuoWorkflow']['Service']['Headers']
                metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                expect(metadata).to include(
                  'provider' => 'gitlab',
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'identifier' => 'claude_sonnet_3_7_20250219'
                )
              end

              it_behaves_like 'ServiceURI has the right value', false
            end
          end

          context 'when a model selection setting does not exist' do
            context 'when provided as param[:root_namespace_id]' do
              subject(:get_response) do
                get api(path, user), headers: workhorse_headers, params: { root_namespace_id: model_selection_group.id }
              end

              it 'includes model metadata headers with default model' do
                get_response

                expect(response).to have_gitlab_http_status(:ok)

                headers = json_response['DuoWorkflow']['Service']['Headers']

                metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                expect(metadata).to include(
                  'provider' => 'gitlab',
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'identifier' => nil
                )
              end

              it_behaves_like 'ServiceURI has the right value', false
            end

            context 'when a user_selected_model_identifier is provided' do
              subject(:get_response) do
                get api(path, user), headers: workhorse_headers, params: {
                  root_namespace_id: model_selection_group.id,
                  user_selected_model_identifier: user_selected_model_identifier
                }
              end

              context 'when a valid user_selected_model_identifier is provided' do
                let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

                it 'uses the user-selected model' do
                  get_response

                  expect(response).to have_gitlab_http_status(:ok)

                  headers = json_response['DuoWorkflow']['Service']['Headers']
                  metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                  expect(metadata).to include(
                    'provider' => 'gitlab',
                    'feature_setting' => 'duo_agent_platform_agentic_chat',
                    'identifier' => user_selected_model_identifier
                  )
                end

                it_behaves_like 'ServiceURI has the right value', false
              end

              context 'when an invalid user_selected_model_identifier is provided' do
                let(:user_selected_model_identifier) { 'invalid-model-for-duo-agent-platform' }

                it 'uses the default model' do
                  get_response

                  expect(response).to have_gitlab_http_status(:ok)

                  headers = json_response['DuoWorkflow']['Service']['Headers']
                  metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                  expect(metadata).to include(
                    'provider' => 'gitlab',
                    'feature_setting' => 'duo_agent_platform_agentic_chat',
                    'identifier' => nil
                  )
                end

                it_behaves_like 'ServiceURI has the right value', false
              end

              context 'when an empty user_selected_model_identifier is provided' do
                let(:user_selected_model_identifier) { '' }

                it 'uses the default model' do
                  get_response

                  expect(response).to have_gitlab_http_status(:ok)

                  headers = json_response['DuoWorkflow']['Service']['Headers']
                  metadata = ::Gitlab::Json.parse(headers['x-gitlab-agent-platform-model-metadata'])
                  expect(metadata).to include(
                    'provider' => 'gitlab',
                    'feature_setting' => 'duo_agent_platform_agentic_chat',
                    'identifier' => nil
                  )
                end

                it_behaves_like 'ServiceURI has the right value', false
              end
            end
          end
        end
      end

      context 'for X-Gitlab-Agent-Platform-Feature-Setting-Name header', :saas do
        context 'when X-Gitlab-Agent-Platform-Feature-Setting-Name header is provided', :request_store do
          let(:custom_feature_name) { 'any_dap_feature' }

          before do
            ::Gitlab::Auth::Identity.link_from_scoped_user(service_account, user, context: :authentication)
          end

          it 'uses the header value as feature_name when calling DuoAgentPlatformModelMetadataService' do
            expect(::Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).to receive(:new).with(
              hash_including(feature_name: custom_feature_name.to_sym)
            ).and_call_original

            get api(path, user),
              headers: workhorse_headers.merge('X-Gitlab-Agent-Platform-Feature-Setting-Name' => custom_feature_name)
          end

          it 'uses the header value when calling FeatureSettingSelectionService' do
            expect(::Ai::FeatureSettingSelectionService).to receive(:new).with(
              user,
              custom_feature_name.to_sym,
              anything
            ).and_call_original

            get api(path, user), headers: workhorse_headers.merge(
              'X-Gitlab-Agent-Platform-Feature-Setting-Name' => custom_feature_name
            ), params: { root_namespace_id: group.id }
          end

          it 'uses a composite identity token' do
            expect_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
              expect(service).to receive(:generate_oauth_token_with_composite_identity_support)
                .and_call_original

              expect(service).not_to receive(:generate_oauth_token)
            end

            get api(path, user), headers: workhorse_headers.merge(
              'X-Gitlab-Agent-Platform-Feature-Setting-Name' => custom_feature_name
            ), params: { root_namespace_id: group.id }
          end
        end

        context 'when X-Gitlab-Agent-Platform-Feature-Setting-Name header is missing' do
          let(:custom_feature_name) { 'duo_agent_platform' }

          it 'uses a regular non-composite identity token' do
            expect_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
              expect(service).to receive(:generate_oauth_token)
                .and_call_original

              expect(service).not_to receive(:generate_oauth_token_with_composite_identity_support)
            end

            get api(path, user), headers: workhorse_headers.merge(
              'X-Gitlab-Agent-Platform-Feature-Setting-Name' => nil
            ), params: { root_namespace_id: group.id }
          end
        end

        context 'when X-Gitlab-Agent-Platform-Feature-Setting-Name header is not provided' do
          it 'defaults to agentic_chat_feature_name when calling DuoAgentPlatformModelMetadataService' do
            expect(::Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).to receive(:new).with(
              hash_including(feature_name: ::Ai::ModelSelection::FeaturesConfigurable.agentic_chat_feature_name)
            ).and_call_original

            get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }
          end

          it 'defaults to agentic_chat_feature_name when calling FeatureSettingSelectionService' do
            expect(::Ai::FeatureSettingSelectionService).to receive(:new).with(
              user,
              ::Ai::ModelSelection::FeaturesConfigurable.agentic_chat_feature_name,
              anything
            ).and_call_original

            get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }
          end

          it 'uses a regular non-composite identity token' do
            expect_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
              expect(service).to receive(:generate_oauth_token)
                .and_call_original

              expect(service).not_to receive(:generate_oauth_token_with_composite_identity_support)
            end

            get api(path, user), headers: workhorse_headers, params: { root_namespace_id: group.id }
          end
        end
      end

      context 'for x-gitlab-model-prompt-cache-enabled at group-level' do
        it 'returns true in x-gitlab-model-prompt-cache-enabled header' do
          group.namespace_settings.update_column(:model_prompt_cache_enabled, true)

          get api(path, user), headers: workhorse_headers, params: { namespace_id: group.id }

          expect(
            json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-model-prompt-cache-enabled']
          ).to eq('true')
        end

        it 'returns false in x-gitlab-model-prompt-cache-enabled header' do
          group.namespace_settings.update_column(:model_prompt_cache_enabled, false)

          get api(path, user), headers: workhorse_headers, params: { namespace_id: group.id }

          expect(
            json_response['DuoWorkflow']['Service']['Headers']['x-gitlab-model-prompt-cache-enabled']
          ).to eq('false')
        end
      end
    end

    context 'when CreateOauthAccessTokenService returns an error' do
      before do
        allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'Failed to generate OAuth token', http_status: :unauthorized) # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
          )
        end
      end

      it 'returns an error response' do
        get api(path, user), headers: workhorse_headers

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(json_response['message']).to eq('Failed to generate OAuth token')
      end
    end

    context 'when Workhorse header is missing' do
      it 'returns an error response' do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when authenticated with a token that has the ai_workflows scope' do
      it 'is allowed' do
        get api(path, oauth_access_token: ai_workflows_oauth_token), headers: workhorse_headers

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    describe 'ai_workflows scope path condition' do
      # Exact match against the configured relative URL root (any depth).
      let(:relative_url_root) { '' }
      let(:request_method) { :get }
      let(:condition) do
        allow(Gitlab.config.gitlab).to receive(:relative_url_root).and_return(relative_url_root)
        scope = described_class.allowed_scopes.find { |s| s.name == :ai_workflows && s.if }
        scope.if.call(
          instance_double(
            Rack::Request,
            get?: request_method == :get,
            post?: request_method == :post,
            path: request_path
          )
        )
      end

      context 'without a relative URL root' do
        let(:request_path) { '/api/v4/ai/duo_workflows/ws' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'with a single-segment relative URL root' do
        let(:relative_url_root) { '/gitlab' }
        let(:request_path) { '/gitlab/api/v4/ai/duo_workflows/ws' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'with a multi-segment relative URL root' do
        let(:relative_url_root) { '/gitlab/instance' }
        let(:request_path) { '/gitlab/instance/api/v4/ai/duo_workflows/ws' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'for a foreign prefix that only ends with the endpoint path' do
        let(:request_path) { '/evil/api/v4/ai/duo_workflows/ws' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for the trace.jsonl endpoint' do
        let(:request_path) { '/api/v4/ai/duo_workflows/workflows/1/trace.jsonl' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'for the trace.jsonl endpoint with a relative URL root' do
        let(:relative_url_root) { '/gitlab' }
        let(:request_path) { '/gitlab/api/v4/ai/duo_workflows/workflows/42/trace.jsonl' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'for a path that only ends with trace.jsonl but has a foreign prefix' do
        let(:request_path) { '/evil/api/v4/ai/duo_workflows/workflows/1/trace.jsonl' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for a path that looks like trace.jsonl but has extra segments' do
        let(:request_path) { '/api/v4/ai/duo_workflows/workflows/1/trace.jsonl/extra' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for a non-GET request to trace.jsonl' do
        let(:request_method) { :post }
        let(:request_path) { '/api/v4/ai/duo_workflows/workflows/1/trace.jsonl' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for the execute endpoint' do
        let(:request_method) { :post }
        let(:request_path) { '/api/v4/ai/duo_workflows/workflows/1/execute' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'for the execute endpoint with a relative URL root' do
        let(:request_method) { :post }
        let(:relative_url_root) { '/gitlab' }
        let(:request_path) { '/gitlab/api/v4/ai/duo_workflows/workflows/42/execute' }

        it 'grants the scope' do
          expect(condition).to be(true)
        end
      end

      context 'for a path that only ends with execute but has a foreign prefix' do
        let(:request_method) { :post }
        let(:request_path) { '/evil/api/v4/ai/duo_workflows/workflows/1/execute' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for a path that looks like execute but has extra segments' do
        let(:request_method) { :post }
        let(:request_path) { '/api/v4/ai/duo_workflows/workflows/1/execute/extra' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for a GET request to the execute endpoint' do
        let(:request_path) { '/api/v4/ai/duo_workflows/workflows/1/execute' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end

      context 'for a request that is neither GET nor POST' do
        let(:request_method) { :delete }
        let(:request_path) { '/api/v4/ai/duo_workflows/ws' }

        it 'does not grant the scope' do
          expect(condition).to be(false)
        end
      end
    end
  end

  describe 'POST /ai/duo_workflows/workflows/:workflow_id/execute' do
    let_it_be(:executed_workflow) { create(:duo_workflows_workflow, user: user, project: project) }

    let(:workflow_id) { executed_workflow.id }
    let(:path) { "/ai/duo_workflows/workflows/#{workflow_id}/execute" }
    let(:request_params) { {} }

    include_context 'workhorse headers'
    include_context 'with user governing namespace' do
      let(:governing_namespace) { group }
    end

    subject(:execute_request) { post api(path, user), headers: workhorse_headers, params: request_params }

    before do
      allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.success(payload: {
            oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'oauth_token')
          })
        )
      end

      allow(Gitlab::DuoWorkflow::Client).to receive_messages(
        self_hosted_url: nil,
        default_service_url: 'cloud.gitlab.com:50052',
        secure?: true
      )

      allow(Gitlab.config.duo_workflow).to receive(:service_url).and_return(duo_workflow_service_url)

      allow(::CloudConnector::Tokens).to receive(:get).and_return('token')
    end

    context 'when the caller owns the workflow' do
      it 'returns the connection details Workhorse needs', :aggregate_failures do
        execute_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.media_type).to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)

        config = json_response['DuoWorkflow']
        expect(config['Service']['URI']).to eq(duo_workflow_service_url)
        expect(config['Service']['Secure']).to be(true)
        expect(config['Service']['Headers']).to include(
          'x-gitlab-oauth-token' => 'oauth_token',
          'authorization' => 'Bearer token',
          'x-gitlab-unidirectional-streaming' => 'enabled'
        )
        expect(config['LockConcurrentFlow']).to be(true)
      end

      # Workhorse authorizes nothing itself, so the ID it starts the flow with has
      # to come from here rather than from the caller's request body.
      it 'pins the workflow ID for Workhorse' do
        execute_request

        expect(json_response['DuoWorkflow']['WorkflowID']).to eq(executed_workflow.id.to_s)
      end

      # This endpoint reaches the same flag push as :ws, through the shared
      # duo_workflow_connection_config, and it is the path Workhorse actually calls.
      # Covered here so decoupling the two call sites cannot silently drop the flag.
      describe 'pushing duo_developer_model_routing' do
        let(:feature_setting_name) { 'duo_developer' }

        subject(:pushed_flags) do
          post api(path, user),
            headers: workhorse_headers.merge(
              'X-Gitlab-Agent-Platform-Feature-Setting-Name' => feature_setting_name
            ),
            params: request_params

          expect(response).to have_gitlab_http_status(:ok)

          json_response.dig('DuoWorkflow', 'Service', 'Headers', 'x-gitlab-enabled-feature-flags').to_s.split(',')
        end

        before do
          stub_feature_flags(duo_developer_model_routing: user)
        end

        it 'pushes the flag for the duo_developer flow' do
          expect(pushed_flags).to include('duo_developer_model_routing')
        end

        context 'when the session is for another flow' do
          let(:feature_setting_name) { 'duo_agent_platform' }

          it 'does not push the flag' do
            expect(pushed_flags).not_to include('duo_developer_model_routing')
          end
        end
      end

      # The definition selects the MCP tool set and the minted token's feature, and the
      # workflow is already pinned, so the body must not be able to swap in another flow's.
      context 'when the request body carries a different workflow definition' do
        let(:request_params) { { workflow_definition: 'chat' } }

        it 'builds the MCP config from the workflow record' do
          expect(::Ai::DuoWorkflows::McpConfigService).to receive(:new)
            .with(user, anything, hash_including(workflow_definition: 'software_development'))
            .and_call_original

          execute_request

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'mints the token for the workflow record definition' do
          expect(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new)
            .with(hash_including(workflow_definition: 'software_development'))
            .and_call_original

          execute_request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      it_behaves_like 'authorizing granular token permissions', :read_duo_workflow_websocket do
        let(:boundary_object) { :user }
        let(:request) do
          post api(path, personal_access_token: pat), headers: workhorse_headers, params: request_params
        end
      end
    end

    context 'when the workflow belongs to another user' do
      let_it_be(:other_user) { create(:user, maintainer_of: project) }
      let_it_be(:other_workflow) { create(:duo_workflows_workflow, user: other_user, project: project) }

      let(:workflow_id) { other_workflow.id }

      it 'returns not found' do
        execute_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the workflow does not exist' do
      let(:workflow_id) { non_existing_record_id }

      it 'returns not found' do
        execute_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the request does not come through Workhorse' do
      it 'is forbidden', :aggregate_failures do
        post api(path, user), params: request_params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Request should be executed via GitLab Workhorse')
      end
    end

    # The tag opts out of the harness that injects a valid Workhorse JWT into
    # every request spec, so the JWT guard itself is exercised.
    context 'when the Workhorse JWT is missing', :verify_workhorse_jwt do
      it 'is forbidden' do
        post api(path, user), headers: { 'GitLab-Workhorse' => '1.0' }, params: request_params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'is unauthorized' do
        post api(path), headers: workhorse_headers, params: request_params

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when authenticated with a token that has the ai_workflows scope' do
      it 'is allowed' do
        post api(path, oauth_access_token: ai_workflows_oauth_token), headers: workhorse_headers,
          params: request_params

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when authenticated with a token that lacks the ai_workflows scope' do
      let_it_be(:read_api_oauth_token) { create(:oauth_access_token, user: user, scopes: [:read_api]) }

      it 'is forbidden' do
        post api(path, oauth_access_token: read_api_oauth_token), headers: workhorse_headers,
          params: request_params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when current_user is a composite identity user' do
      let_it_be(:composite_scopes) { ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ['api'] + ["user:#{user.id}"] }
      let_it_be(:composite_token) do
        create(:oauth_access_token, resource_owner: service_account, scopes: composite_scopes)
      end

      # The token belongs to the service account, but the workflow belongs to the
      # linked human user: authorization has to resolve to the latter.
      it 'authorizes against the linked user' do
        post api(path, oauth_access_token: composite_token), headers: workhorse_headers,
          params: request_params.merge(project_id: project.id)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['DuoWorkflow']['WorkflowID']).to eq(executed_workflow.id.to_s)
      end

      context 'and the workflow belongs to a user the token is not linked to' do
        let_it_be(:unlinked_user) { create(:user, maintainer_of: project) }
        let_it_be(:unlinked_workflow) do
          create(:duo_workflows_workflow, user: unlinked_user, project: project)
        end

        let(:workflow_id) { unlinked_workflow.id }

        it 'returns not found' do
          post api(path, oauth_access_token: composite_token), headers: workhorse_headers,
            params: request_params.merge(project_id: project.id)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when identity verification is required' do
      include_context 'when identity verification blocks the user'

      it 'refuses the request and names identity verification', :aggregate_failures do
        execute_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when rate limited' do
      it 'throttles on the session bootstrap limit, keyed by the caller', :aggregate_failures do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
          .with(anything, anything, :duo_workflow_direct_access, scope: have_attributes(id: user.id))
          .and_return(true)

        execute_request

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(response.headers)
          .to include('Retry-After' => Gitlab::ApplicationRateLimiter.period_for(:duo_workflow_direct_access))
      end
    end
  end

  describe 'GET /ai/duo_workflows/list_tools' do
    let(:path) { '/ai/duo_workflows/list_tools' }

    let(:get_without_params) { get api(path, user) }
    let(:get_with_definition) { get api(path, user), params: { workflow_definition: workflow_definition } }

    before do
      allow(Gitlab.config.duo_workflow).to receive(:service_url).and_return duo_workflow_service_url
      stub_config(duo_workflow: {
        service_url: duo_workflow_service_url,
        secure: true
      })
    end

    context 'when identity verification is required' do
      include_context 'when identity verification blocks the user'

      it 'names identity verification in the error', :aggregate_failures do
        get_without_params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when rate limited' do
      it 'returns api error' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_return(true)

        get_without_params

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(response.headers)
          .to include(
            'Retry-After' => Gitlab::ApplicationRateLimiter.period_for(:duo_workflow_direct_access)
          )
      end
    end

    context 'when DuoWorkflowService returns error' do
      it 'returns api error' do
        expect_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          expect(client).to receive(:list_tools).and_return({
            status: :error,
            message: "could not list tools"
          })
        end

        get_without_params

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when success' do
      let(:payload) do
        {
          'tools' => [
            { 'name' => 'read_write_files' },
            { 'name' => 'run_commands' }
          ],
          'evalDataset' => [
            { 'tool_name' => 'read_write_files' }
          ]
        }
      end

      before do
        allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          allow(client).to receive(:list_tools).and_return(ServiceResponse.success(payload: payload))
        end
      end

      it 'returns tools payload' do
        get_without_params

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq(payload)
      end

      it_behaves_like 'authorizing granular token permissions', :read_duo_workflow_tool do
        let(:boundary_object) { :user }
        let(:request) { get api(path, personal_access_token: pat) }
      end

      context 'when authenticated with a token that has the ai_workflows scope' do
        it 'is forbidden' do
          get api(path, oauth_access_token: ai_workflows_oauth_token)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end
  end

  describe 'POST /ai/duo_workflows/workflows/:workflow_id/resume' do
    let(:input_required_workflow) do
      create(:duo_workflows_workflow, user: user, project: project, status: 6)
    end

    let(:path) { "/ai/duo_workflows/workflows/#{input_required_workflow.id}/resume" }
    let(:params) { { human_approval: true, human_message: 'looks good' } }

    before do
      project.project_setting.update!(duo_remote_flows_enabled: true)
      allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
        allow(client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: { token: 'an-encrypted-token' })
        )
      end
      allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.success(
            payload: {
              oauth_access_token: instance_double('Doorkeeper::AccessToken', plaintext_token: 'oauth_token')
            }
          )
        )
      end
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)

      pipeline = create(:ci_pipeline, :success, project: project)
      workload = create(:ci_workload, pipeline: pipeline, project: project)
      input_required_workflow.workflows_workloads.create!(workload: workload, project: project)
    end

    context 'when workflow is not found' do
      let(:path) { "/ai/duo_workflows/workflows/#{non_existing_record_id}/resume" }

      it 'returns 404' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when identity verification is required' do
      include_context 'when identity verification blocks the user'

      before do
        # find_workflow! only reaches the identity verification branch once the read ability has failed
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_duo_workflow, input_required_workflow).and_return(false)
      end

      it 'refuses to resume and names identity verification', :aggregate_failures do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when workflow is not in input_required state' do
      let(:input_required_workflow) do
        create(:duo_workflows_workflow, user: user, project: project, status: 1)
      end

      it 'returns 403' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when workflow is in input_required state but has no completed workload pipeline' do
      let(:input_required_workflow) do
        workflow = create(:duo_workflows_workflow, user: user, project: project, status: 6)
        pipeline = create(:ci_pipeline, project: project)
        workload = create(:ci_workload, pipeline: pipeline, project: project)
        workflow.workflows_workloads.create!(workload: workload, project: project)
        workflow
      end

      it 'returns 403' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when human_approval is missing' do
      it 'returns 400' do
        post api(path, user), params: params.except(:human_approval)

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when no catalog item is found for the workflow' do
      it 'returns 404' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['message']).to include('AI Catalog item not found for this workflow')
      end
    end

    context 'with a catalog workflow' do
      let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }
      let_it_be(:consumer) do
        create(:ai_catalog_item_consumer, item: flow, project: project, pinned_version_prefix: nil)
      end

      let(:input_required_workflow) do
        create(:duo_workflows_workflow, user: user, project: project, status: 6,
          ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      it 'calls Flows::ExecuteService with resume_context' do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: project,
          current_user: user,
          params: hash_including(
            resume_context: hash_including(
              existing_workflow: input_required_workflow,
              human_approval: true,
              human_message: 'looks good'
            )
          )
        ).and_return(
          instance_double(
            ::Ai::Catalog::Flows::ExecuteService,
            execute: ServiceResponse.success(payload: { workflow: input_required_workflow, workload_id: 123 })
          )
        )

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['id']).to eq(input_required_workflow.id)
      end

      %i[plan_approval_required tool_call_approval_required].each do |status|
        context "when the workflow is waiting in #{status}" do
          let(:input_required_workflow) do
            create(:duo_workflows_workflow, status, user: user, project: project,
              ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
          end

          let(:params) { { human_approval: true } }

          it 'resumes the session' do
            allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
              allow(svc).to receive(:execute).and_return(
                ServiceResponse.success(payload: { workflow: input_required_workflow, workload_id: 123 })
              )
            end

            post api(path, user), params: params

            expect(response).to have_gitlab_http_status(:created)
          end
        end
      end

      it_behaves_like 'authorizing granular token permissions', :resume_duo_workflow do
        let(:boundary_object) { :user }
        let(:request) do
          post api(path, personal_access_token: pat), params: params
        end

        before do
          allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.success(payload: { workflow: input_required_workflow, workload_id: 123 })
            )
          end
        end
      end

      # Backs the `send_duo_session_input` MCP tool, which calls this endpoint with an mcp-scoped token.
      it_behaves_like 'an endpoint with mcp route setting', :resume_duo_workflow,
        expected_params: [:workflow_id, :human_approval, :human_message], status: :created do
        subject { post api(path, user), params: params }

        before do
          # The shared example replays the request, so stub every instance rather than the next one.
          allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(
            instance_double(
              ::Ai::Catalog::Flows::ExecuteService,
              execute: ServiceResponse.success(payload: { workflow: input_required_workflow, workload_id: 123 })
            )
          )
        end
      end

      context 'when workflow execution returns error' do
        before do
          allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Something went wrong', reason: :validation_error)
            )
          end
        end

        it 'returns 400' do
          post api(path, user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('Something went wrong')
        end
      end
    end

    context 'with a project-level catalog consumer with a parent group consumer' do
      let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }
      let_it_be(:group_service_account) do
        create(:user, :service_account, composite_identity_enforced: true, provisioned_by_group: group)
      end

      let_it_be(:group_consumer) do
        create(:ai_catalog_item_consumer, item: flow, group: group, service_account: group_service_account)
      end

      let_it_be(:project_consumer) do
        create(:ai_catalog_item_consumer, item: flow, project: project, parent_item_consumer: group_consumer)
      end

      let(:input_required_workflow) do
        create(:duo_workflows_workflow, user: user, project: project, status: 6,
          ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
        project.project_setting.update!(duo_features_enabled: true)
      end

      it 'uses the parent group consumer service account' do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: project,
          current_user: user,
          params: hash_including(
            item_consumer: project_consumer,
            service_account: group_service_account
          )
        ).and_return(
          instance_double(
            ::Ai::Catalog::Flows::ExecuteService,
            execute: ServiceResponse.success(payload: { workflow: input_required_workflow, workload_id: 456 })
          )
        )

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
      end
    end

    context 'when only a group consumer exists for the flow' do
      let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }
      let_it_be(:group_service_account) do
        create(:user, :service_account, composite_identity_enforced: true, provisioned_by_group: group)
      end

      let_it_be(:group_consumer) do
        create(:ai_catalog_item_consumer, item: flow, group: group, service_account: group_service_account)
      end

      let(:input_required_workflow) do
        create(:duo_workflows_workflow, user: user, project: project, status: 6,
          ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
        project.project_setting.update!(duo_features_enabled: true)
      end

      it 'uses the group consumer service account directly' do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: project,
          current_user: user,
          params: hash_including(
            item_consumer: group_consumer,
            service_account: group_service_account
          )
        ).and_return(
          instance_double(
            ::Ai::Catalog::Flows::ExecuteService,
            execute: ServiceResponse.success(payload: { workflow: input_required_workflow, workload_id: 457 })
          )
        )

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
      end
    end

    context 'when catalog item exists but consumer is not found' do
      let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }

      let(:input_required_workflow) do
        create(:duo_workflows_workflow, user: user, project: project, status: 6,
          ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      it 'returns 404 with consumer not found message' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['message']).to include('AI Catalog consumer not found for this workflow')
      end
    end
  end

  describe 'POST /ai/duo_workflows/workflows/:workflow_id/restart' do
    let(:failed_workflow) { create(:duo_workflows_workflow, :failed, user: user, project: project) }
    let(:path) { "/ai/duo_workflows/workflows/#{failed_workflow.id}/restart" }

    before do
      project.project_setting.update!(duo_remote_flows_enabled: true)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    end

    context 'when workflow is not found' do
      let(:path) { "/ai/duo_workflows/workflows/#{non_existing_record_id}/restart" }

      it 'returns 404' do
        post api(path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when workflow is neither failed nor stopped' do
      let(:running_workflow) { create(:duo_workflows_workflow, :running, user: user, project: project) }
      let(:path) { "/ai/duo_workflows/workflows/#{running_workflow.id}/restart" }

      it 'returns 403' do
        post api(path, user)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when no catalog item is found for the workflow' do
      it 'returns 404 without starting a new session', :aggregate_failures do
        failed_workflow

        expect { post api(path, user) }.not_to change { Ai::DuoWorkflows::Workflow.count }

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['message']).to include('AI Catalog item not found for this workflow')
        expect(failed_workflow.reload).to be_failed
      end
    end

    context 'with a catalog workflow' do
      let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }
      let_it_be(:consumer) do
        create(:ai_catalog_item_consumer, item: flow, project: project, pinned_version_prefix: nil)
      end

      let_it_be(:issue) { create(:issue, project: project) }

      let(:failed_workflow) do
        create(:duo_workflows_workflow, :failed, user: user, project: project, goal: 'Fix the bug', issue: issue,
          summary: 'It broke', ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      let(:new_workflow) do
        create(:duo_workflows_workflow, :running, user: user, project: project, goal: 'Fix the bug', issue: issue,
          ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      let(:execute_result) { ServiceResponse.success(payload: { workflow: new_workflow, workload_id: 123 }) }

      before do
        create(:duo_workflows_checkpoint, workflow: failed_workflow, project: project)

        allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
          allow(svc).to receive(:execute).and_return(execute_result)
        end
      end

      it 'starts a new session with the same flow, goal and noteable', :aggregate_failures do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: project,
          current_user: user,
          params: hash_including(
            item_consumer: consumer,
            user_prompt: 'Fix the bug',
            issue_id: issue.iid,
            event_type: 'api_execution'
          )
        ).and_return(instance_double(::Ai::Catalog::Flows::ExecuteService, execute: execute_result))

        post api(path, user)

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['id']).to eq(new_workflow.id)
        expect(json_response['status']).to eq('running')
        expect(json_response['workload']['id']).to eq(123)
      end

      it 'leaves the original workflow untouched', :aggregate_failures do
        post api(path, user)

        failed_workflow.reload
        expect(failed_workflow).to be_failed
        expect(failed_workflow.summary).to eq('It broke')
        expect(failed_workflow.checkpoints.count).to eq(1)
      end

      it_behaves_like 'authorizing granular token permissions', :restart_duo_workflow do
        let(:boundary_object) { :user }
        let(:request) do
          post api(path, personal_access_token: pat)
        end
      end

      context 'when identity verification is required' do
        include_context 'when identity verification blocks the user'

        it 'returns 403 without starting a new session', :aggregate_failures do
          expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

          expect { post api(path, user) }.not_to change { Ai::DuoWorkflows::Workflow.count }

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to include('Identity verification is required')
        end
      end

      context 'when the restart service denies the request' do
        before do
          allow_next_instance_of(::Ai::DuoWorkflows::RestartWorkflowService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Can not restart workflow', reason: :forbidden)
            )
          end
        end

        it 'returns 403' do
          post api(path, user)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when a restart of the same workflow is already in progress' do
        before do
          allow_next_instance_of(Gitlab::ExclusiveLease) do |lease|
            allow(lease).to receive(:try_obtain).and_return(nil)
          end
        end

        it 'returns 409' do
          post api(path, user)

          expect(response).to have_gitlab_http_status(:conflict)
        end
      end

      context 'when starting the new session returns an error' do
        let(:execute_result) { ServiceResponse.error(message: 'Something went wrong', reason: :validation_error) }

        it 'returns 400 and leaves the original workflow untouched', :aggregate_failures do
          post api(path, user)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('Something went wrong')
          expect(failed_workflow.reload).to be_failed
        end
      end
    end
  end

  describe 'GET /ai/duo_workflows/workflows/:workflow_id/trace.jsonl' do
    let(:path) { "/ai/duo_workflows/workflows/#{workflow.id}/trace.jsonl" }

    context 'when identity verification blocks reading a session the user owns' do
      include_context 'when identity verification blocks the user'

      before do
        # find_workflow! only reaches the identity verification branch once the read ability has failed
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_duo_workflow, workflow).and_return(false)
      end

      it 'names identity verification rather than returning a bare 403', :aggregate_failures do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end

      it 'names it on the full=true path, which looks the session up by owner', :aggregate_failures do
        get api("#{path}?full=true", user)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when the workflow has no checkpoints and no goal' do
      before do
        workflow.update!(goal: nil)
      end

      it 'returns an empty body with application/x-ndjson content type', :aggregate_failures do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.content_type).to include('application/x-ndjson')
        expect(response.body).to eq('')
      end
    end

    context 'when the workflow has a goal' do
      it 'returns the goal as the first line with channel "goal"' do
        get api(path, user)

        first_line = Gitlab::Json.parse(response.body.lines.first)
        expect(first_line).to eq('channel' => 'goal', 'value' => workflow.reload.goal)
      end
    end

    context 'when the latest checkpoint has a ui_chat_log' do
      let_it_be(:checkpoint) do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { channel_values: { ui_chat_log: [
            { status: 'success', content: 'step one', message_type: 'human' },
            { status: 'success', content: 'step two', message_type: 'ai' }
          ] } },
          metadata: { step: 1, source: 'loop', parents: {} })
      end

      it 'returns one JSONL line per ui_chat_log entry with channel property', :aggregate_failures do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.content_type).to include('application/x-ndjson')

        lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
        channel_lines = lines.reject { |l| l['channel'] == 'goal' }
        expect(channel_lines.length).to eq(2)
        expect(channel_lines[0]).to include('channel' => 'ui_chat_log', 'content' => 'step one')
        expect(channel_lines[1]).to include('channel' => 'ui_chat_log', 'content' => 'step two')
      end

      context 'when an earlier checkpoint exists' do
        before do
          # Use a fixed thread_ts that lexicographically precedes any real UUIDv7
          # (current timestamps produce "019..." or "018..." prefixes).
          # The latest checkpoint is cumulative and already contains all data.
          create(:duo_workflows_checkpoint, workflow: workflow, project: project,
            thread_ts: '00000000-0000-7000-0000-000000000001',
            checkpoint: { channel_values: { ui_chat_log: [{ status: 'success', content: 'step zero' }] } },
            metadata: { step: 0, source: 'loop', parents: {} })
        end

        it 'returns only data from the latest checkpoint' do
          get api(path, user)

          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          content_lines = lines.reject { |l| l['channel'] == 'goal' }
          expect(content_lines.map { |l| l['content'] }).to match_array(['step one', 'step two'])
        end
      end
    end

    context 'when the latest checkpoint has multiple channels' do
      let_it_be(:checkpoint) do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { channel_values: {
            ui_chat_log: [{ status: 'success', content: 'hello', message_type: 'human' }],
            status: 'running',
            plan: { 'steps' => [] }
          } },
          metadata: { step: 0, source: 'loop', parents: {} })
      end

      it 'returns lines for all channels with a channel property', :aggregate_failures do
        get api(path, user)

        lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
        channels = lines.map { |l| l['channel'] }

        expect(channels).to include('ui_chat_log', 'status', 'plan')
        expect(lines.find { |l| l['channel'] == 'ui_chat_log' }).to include('content' => 'hello')
        expect(lines.find { |l| l['channel'] == 'status' }).to include('value' => 'running')
        expect(lines.find { |l| l['channel'] == 'plan' }).to include('value' => { 'steps' => [] })
      end
    end

    context 'when a channel value is a hash containing sub-arrays' do
      let_it_be(:checkpoint) do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { channel_values: {
            conversation_history: {
              developer_agent: [
                { type: 'AIMessage', content: 'step one' },
                { type: 'ToolMessage', content: 'result' }
              ]
            }
          } },
          metadata: { step: 0, source: 'loop', parents: {} })
      end

      it 'expands sub-arrays into individual lines with dotted channel names', :aggregate_failures do
        get api("#{path}?full=true", user)

        lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
        channel_lines = lines.reject { |l| l['channel'] == 'goal' }
        expect(channel_lines.length).to eq(2)
        expect(channel_lines[0]).to include('channel' => 'conversation_history.developer_agent', 'type' => 'AIMessage')
        expect(channel_lines[1]).to include('channel' => 'conversation_history.developer_agent',
          'type' => 'ToolMessage')
      end
    end

    context 'with internal channels and the full parameter' do
      let_it_be(:checkpoint) do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { channel_values: {
            ui_chat_log: [{ status: 'success', content: 'hello', message_type: 'human' }],
            status: 'running',
            plan: { 'steps' => [] },
            conversation_history: {
              developer_agent: [{ type: 'ToolMessage', content: 'secret-bearing tool output' }]
            },
            handover: [{ type: 'SystemMessage', content: 'handover summary' }]
          } },
          metadata: { step: 0, source: 'loop', parents: {} })
      end

      context 'when the owner omits the full parameter' do
        it 'returns only safe channels' do
          get api(path, user)

          channels = response.body.split("\n").map { |l| Gitlab::Json.parse(l)['channel'] }
          expect(channels).to include('ui_chat_log', 'status', 'plan', 'goal')
          expect(channels).not_to include(a_string_starting_with('conversation_history'), 'handover')
        end
      end

      context 'when the owner requests full=true' do
        it 'returns all channels' do
          get api("#{path}?full=true", user)

          channels = response.body.split("\n").map { |l| Gitlab::Json.parse(l)['channel'] }
          expect(channels).to include('ui_chat_log', 'status', 'plan', 'goal',
            'conversation_history.developer_agent', 'handover')
        end
      end

      context 'when a non-owner with pipeline access requests full=true' do
        let_it_be(:other_user) { create(:user, maintainer_of: project) }

        before do
          workflow.update!(environment: :web)
        end

        it 'returns 404 not found' do
          get api("#{path}?full=true", other_user)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when a non-owner with pipeline access omits the full parameter' do
        let_it_be(:other_user) { create(:user, maintainer_of: project) }

        before do
          workflow.update!(environment: :web)
        end

        it 'returns only safe channels' do
          get api(path, other_user)

          channels = response.body.split("\n").map { |l| Gitlab::Json.parse(l)['channel'] }
          expect(channels).to include('ui_chat_log', 'status', 'plan', 'goal')
          expect(channels).not_to include(a_string_starting_with('conversation_history'), 'handover')
        end
      end
    end

    context 'when the workflow is a private messaging session (slack)' do
      before do
        workflow.update!(environment: :web, messaging_callback_context: { 'adapter' => 'slack' })
      end

      it 'stays readable by the invoker' do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:ok)
      end

      context 'when requested by a non-owner with pipeline access' do
        let_it_be(:other_user) { create(:user, maintainer_of: project) }

        it 'returns 404, indistinguishable from an unknown id', :aggregate_failures do
          get api(path, other_user)

          expect(response).to have_gitlab_http_status(:not_found)

          get api("/ai/duo_workflows/workflows/#{non_existing_record_id}/trace.jsonl", other_user)
          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'with incremental checkpoint blobs' do
      # The header carries different content than the blobs so we can tell which
      # source the trace was built from.
      let_it_be(:checkpoint) do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project, current_thread: 0,
          checkpoint: { channel_values: { ui_chat_log: [{ content: 'from header' }] } },
          metadata: { step: 1, source: 'loop', parents: {} })
      end

      def compressed_json(value)
        Zlib::Deflate.deflate(Gitlab::Json.dump(value))
      end

      # thread_ts matches the header below so the ancestor walk keeps the blobs on-path.
      def create_blob(version:, content:)
        create(:duo_workflows_checkpoint_blob, workflow: workflow, project: project,
          channel: 'ui_chat_log', version: version, current_thread: 0, thread_ts: 'ts-1',
          write_type: 'json', step_action: 'conversation',
          data: compressed_json([{ 'content' => content, 'message_type' => 'ai' }]))
      end

      # Blobs are only read for workflows created with incremental checkpoints
      # enabled (the snapshotted column), so the read path requires it in addition
      # to the read flag.
      before do
        workflow.update!(incremental_checkpoints_enabled: true)
      end

      context 'when the read flag is enabled' do
        before do
          create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
            current_thread: 0, thread_ts: 'ts-1')
          create_blob(version: '1', content: 'from blob one')
          create_blob(version: '2', content: 'from blob two')
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
        end

        it 'reconstructs channel_values from the blobs via the latest header' do
          get api(path, user)

          expect(response).to have_gitlab_http_status(:ok)
          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          contents = lines.select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
          expect(contents).to eq(['from blob one', 'from blob two'])
        end
      end

      context 'when the read flag is enabled but the workflow has incremental checkpoints disabled' do
        before do
          workflow.update!(incremental_checkpoints_enabled: false)
          create_blob(version: '1', content: 'from blob one')
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
        end

        it 'reads channel_values from the checkpoint header, ignoring blobs' do
          get api(path, user)

          expect(response).to have_gitlab_http_status(:ok)
          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          contents = lines.select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
          expect(contents).to eq(['from header'])
        end
      end

      context 'when the read flag is enabled but the workflow has no blobs' do
        before do
          create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
            current_thread: 0, thread_ts: 'ts-1')
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
        end

        it 'returns no ui_chat_log because the slim header carries no channel_values' do
          get api(path, user)

          expect(response).to have_gitlab_http_status(:ok)
          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          contents = lines.select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
          expect(contents).to be_empty
        end
      end

      context 'when the read flag is disabled' do
        before do
          create_blob(version: '1', content: 'from blob one')
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
        end

        it 'reads channel_values from the checkpoint header, ignoring blobs' do
          get api(path, user)

          expect(response).to have_gitlab_http_status(:ok)
          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          contents = lines.select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
          expect(contents).to eq(['from header'])
        end
      end

      context 'when the kill switch is on but the trace consumer flag is off' do
        before do
          create_blob(version: '1', content: 'from blob one')
          stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: false)
        end

        it 'reads channel_values from the checkpoint header, ignoring blobs' do
          get api(path, user)

          expect(response).to have_gitlab_http_status(:ok)
          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          contents = lines.select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
          expect(contents).to eq(['from header'])
        end
      end

      context 'with the internal read param' do
        before do
          create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
            current_thread: 0, thread_ts: 'ts-1')
          create_blob(version: '1', content: 'from blob one')
        end

        def contents
          get api(path, user)

          expect(response).to have_gitlab_http_status(:ok)
          lines = response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
          lines.select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
        end

        context 'when read=incremental forces the blob path with the flag off' do
          let(:path) { "/ai/duo_workflows/workflows/#{workflow.id}/trace.jsonl?read=incremental" }

          before do
            stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
          end

          it 'reads channel_values from the blobs' do
            expect(contents).to eq(['from blob one'])
          end
        end

        context 'when read=incremental but the workflow has incremental checkpoints disabled' do
          let(:path) { "/ai/duo_workflows/workflows/#{workflow.id}/trace.jsonl?read=incremental" }

          before do
            workflow.update!(incremental_checkpoints_enabled: false)
            stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)
          end

          it 'falls back to the legacy path instead of returning an empty trace' do
            expect(contents).to eq(['from header'])
          end
        end

        context 'when read=legacy forces the checkpoints table with the flag on' do
          let(:path) { "/ai/duo_workflows/workflows/#{workflow.id}/trace.jsonl?read=legacy" }

          before do
            stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
          end

          it 'reads channel_values from the checkpoint header, ignoring blobs' do
            expect(contents).to eq(['from header'])
          end
        end

        context 'when read is not a recognized value' do
          let(:path) { "/ai/duo_workflows/workflows/#{workflow.id}/trace.jsonl?read=bogus" }

          before do
            stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
          end

          it 'ignores the override and uses the default flag gate' do
            expect(contents).to eq(['from blob one'])
          end
        end
      end
    end

    context 'with blobs spanning multiple threads and a compaction' do
      # Two current_thread groups linked by parent_ts: group 0 holds 'msg a' and
      # status 'running', then a compaction opens group 1 with a ui_chat_log summary
      # snapshot, followed by 'msg b' and status 'completed'.
      def compressed_json(value)
        Zlib::Deflate.deflate(Gitlab::Json.dump(value))
      end

      def create_blob(channel:, thread_ts:, current_thread:, version:, value:, step_action: 'conversation')
        create(:duo_workflows_checkpoint_blob, workflow: workflow, project: project,
          channel: channel, version: version, current_thread: current_thread, thread_ts: thread_ts,
          write_type: 'json', step_action: step_action, data: compressed_json(value))
      end

      def message(content)
        [{ 'content' => content, 'message_type' => 'ai' }]
      end

      before do
        workflow.update!(incremental_checkpoints_enabled: true)

        create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
          current_thread: 0, thread_ts: 'ts-1', parent_ts: 'ts-0', channel_keys: %w[ui_chat_log status])
        create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
          current_thread: 1, thread_ts: 'ts-2', parent_ts: 'ts-1', channel_keys: %w[ui_chat_log status])

        create_blob(channel: 'ui_chat_log', thread_ts: 'ts-1', current_thread: 0, version: '1', value: message('msg a'))
        # A scalar has no delta form, so the gateway stamps every status write 'compaction'.
        create_blob(channel: 'status', thread_ts: 'ts-1', current_thread: 0, version: '2', value: 'running',
          step_action: 'compaction')
        create_blob(channel: 'ui_chat_log', thread_ts: 'ts-2', current_thread: 1, version: '3',
          value: message('summary'), step_action: 'compaction')
        create_blob(channel: 'ui_chat_log', thread_ts: 'ts-2', current_thread: 1, version: '4', value: message('msg b'))
        create_blob(channel: 'status', thread_ts: 'ts-2', current_thread: 1, version: '5', value: 'completed',
          step_action: 'compaction')

        stub_feature_flags(duo_workflow_read_incremental_checkpoints: project, dw_read_blobs_trace: project)
      end

      def trace_lines(query = '')
        get api("#{path}#{query}", user)

        expect(response).to have_gitlab_http_status(:ok)
        response.body.split("\n").map { |l| Gitlab::Json.parse(l) }
      end

      def contents(query = '')
        trace_lines(query).select { |l| l['channel'] == 'ui_chat_log' }.map { |l| l['content'] }
      end

      def statuses(query = '')
        trace_lines(query).select { |l| l['channel'] == 'status' }.map { |l| l['value'] }
      end

      it 'returns the full cross-thread history by default, including the compaction summary' do
        expect(contents).to eq(['msg a', 'summary', 'msg b'])
      end

      it 'keeps every state change in the full trace' do
        expect(statuses).to eq(%w[running completed])
      end

      it 'returns only the latest thread with thread=latest' do
        expect(contents('?thread=latest')).to eq(['summary', 'msg b'])
        expect(statuses('?thread=latest')).to eq(['completed'])
      end

      it 'returns only the requested thread with thread=<current_thread>' do
        expect(contents('?thread=0')).to eq(['msg a'])
        expect(statuses('?thread=0')).to eq(['running'])
      end

      it 'returns no channel data (200) for a non-integer thread instead of erroring' do
        # contents/statuses assert a 200; a non-integer must not reach the integer column.
        expect(contents('?thread=abc')).to be_empty
        expect(statuses('?thread=abc')).to be_empty
      end

      it 'returns no channel data (200) for an all-digit thread outside the int4 range' do
        # current_thread is a Postgres integer column; an out-of-range value would
        # raise ActiveModel::RangeError if it reached the query.
        oversized = (::Gitlab::Database::MAX_INT_VALUE + 1).to_s

        expect(contents("?thread=#{oversized}")).to be_empty
        expect(statuses("?thread=#{oversized}")).to be_empty
      end

      it 'ignores a nested subagent header sharing the same current_thread id' do
        # A nested subagent lineage can reuse a current_thread id independently of
        # the workflow's own groups; only the top-level lineage should be selected.
        create(:duo_workflows_checkpoint_header, workflow: workflow, project: project,
          current_thread: 0, thread_ts: 'ts-nested', checkpoint_ns: 'research_agent:0f8ba4c5')

        expect(contents('?thread=0')).to eq(['msg a'])
        expect(statuses('?thread=0')).to eq(['running'])
      end
    end

    context 'when the trace exceeds the size limit' do
      before do
        stub_const('API::Ai::DuoWorkflows::Workflows::TRACE_MAX_RESPONSE_BYTESIZE', 10)
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { channel_values: { ui_chat_log: [{ content: 'this content exceeds ten bytes' }] } },
          metadata: { step: 0, source: 'loop', parents: {} })
      end

      it 'returns 413' do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:payload_too_large)
      end
    end

    context 'when the checkpoint has no channel_values' do
      let_it_be(:checkpoint) do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { channel_values: {} },
          metadata: { step: 0, source: 'loop', parents: {} })
      end

      before do
        workflow.update!(goal: nil)
      end

      it 'returns an empty body', :aggregate_failures do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to eq('')
      end
    end

    context 'when the user lacks read_duo_workflow permission' do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(false)
      end

      it 'returns 403 forbidden' do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when the user does not own the workflow' do
      let_it_be(:other_user) { create(:user, maintainer_of: project) }

      context 'and the workflow is not from a pipeline' do
        it 'returns 403 forbidden' do
          get api(path, other_user)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'and the workflow is from a pipeline' do
        before do
          workflow.update!(environment: :web)
        end

        it 'returns 200 ok' do
          get api(path, other_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.content_type).to include('application/x-ndjson')
        end
      end
    end

    context 'when the workflow does not exist' do
      let(:path) { "/ai/duo_workflows/workflows/#{non_existing_record_id}/trace.jsonl" }

      it 'returns 404 not found' do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user is not authenticated' do
      it 'returns 401 unauthorized' do
        get api(path)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when authenticated with a token that has the ai_workflows scope' do
      it 'is allowed for the workflow owner' do
        get api(path, oauth_access_token: ai_workflows_oauth_token)

        expect(response).to have_gitlab_http_status(:ok)
      end

      context 'when the token belongs to a different user' do
        let_it_be(:other_user) { create(:user, maintainer_of: project) }
        let_it_be(:other_ai_workflows_token) do
          create(:oauth_access_token, user: other_user, scopes: [:ai_workflows])
        end

        it 'is forbidden' do
          get api(path, oauth_access_token: other_ai_workflows_token)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end

    it_behaves_like 'authorizing granular token permissions', :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { get api(path, personal_access_token: pat) }
    end
  end

  describe 'GET /ai/duo_workflows/workflows/agent_privileges' do
    let(:path) { "/ai/duo_workflows/workflows/agent_privileges" }

    it 'returns a static set of privileges' do
      get api(path, user)

      expect(response).to have_gitlab_http_status(:ok)

      all_privileges_count = ::Ai::DuoWorkflows::Workflow::AgentPrivileges::ALL_PRIVILEGES.count
      expect(json_response['all_privileges'].count).to eq(all_privileges_count)

      privilege1 = json_response['all_privileges'][0]
      expect(privilege1['id']).to eq(1)
      expect(privilege1['name']).to eq('read_write_files')
      expect(privilege1['description']).to eq('Allow local filesystem read/write access')
      expect(privilege1['default_enabled']).to be(true)

      privilege4 = json_response['all_privileges'].find { |p| p['id'] == 4 }
      expect(privilege4['name']).to eq('run_commands')
      expect(privilege4['description']).to eq('Allow running any commands')
      expect(privilege4['default_enabled']).to be(true)
    end

    it_behaves_like 'authorizing granular token permissions',
      :read_duo_workflow_agent_privilege do
      let(:boundary_object) { :user }
      let(:request) { get api(path, personal_access_token: pat) }
    end
  end
end
