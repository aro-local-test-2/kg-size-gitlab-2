# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects::DuoAgentsPlatform', :saas_gitlab_com_subscriptions,
  feature_category: :ai_catalog_curation do
  let_it_be(:developer) { create(:user, :with_namespace) }
  let_it_be(:maintainer) { create(:user, :with_namespace) }
  let_it_be(:reporter) { create(:user, :with_namespace) }
  let_it_be(:guest) { create(:user, :with_namespace) }
  let(:user) { developer }

  let_it_be_with_reload(:group) do
    create(:group_with_plan, plan: :ultimate_trial_plan, trial: true,
      trial_starts_on: Date.current, trial_ends_on: 30.days.from_now,
      developers: developer, maintainers: maintainer, reporters: reporter, guests: guest)
  end

  let_it_be_with_reload(:project) { create(:project, group: group) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true, ai_catalog: true)
    stub_licensed_features(ai_catalog: true, ai_features: true)
    create(:gitlab_subscription_add_on_purchase, :active_trial, :duo_core, namespace: group)
    project.project_setting.update!(duo_remote_flows_enabled: true, duo_features_enabled: true)
    group.namespace_settings.update!(
      duo_features_enabled: true, experiment_features_enabled: true, duo_core_features_enabled: true
    )
    group.ai_settings.update!(duo_agent_platform_enabled: true, duo_workflow_mcp_enabled: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    allow_next_instance_of(Gitlab::Llm::DuoChat) do |instance|
      allow(instance).to receive_messages(credits_available?: true, usage_billing_forbidden?: false)
    end
    sign_in(user)
  end

  describe 'GET /:namespace/:project/-/automate' do
    context 'when duo workflow is enabled' do
      context 'and the user has access to duo_workflow' do
        it 'renders successfully' do
          get project_automate_agent_sessions_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'pushes feature flags to frontend' do
          get project_automate_agent_sessions_path(project)

          expect(response.body).to include('aiCatalogThirdPartyFlows')
        end

        context 'when accessing a specific agent session' do
          let_it_be(:other_project) { create(:project, group: group) }
          let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: developer) }
          let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: other_project, user: developer) }

          it 'renders successfully when the session belongs to the project' do
            get project_automate_path(project, vueroute: "agent-sessions/#{workflow.id}")

            expect(response).to have_gitlab_http_status(:ok)
          end

          it 'returns 404 when the session belongs to a different project' do
            get project_automate_path(project, vueroute: "agent-sessions/#{other_workflow.id}")

            expect(response).to have_gitlab_http_status(:not_found)
          end

          it 'returns 404 when the session does not exist' do
            get project_automate_path(project, vueroute: "agent-sessions/#{non_existing_record_id}")

            expect(response).to have_gitlab_http_status(:not_found)
          end

          it 'returns 404 when the user cannot read the session' do
            foreign_workflow = create(:duo_workflows_workflow, project: project, user: maintainer,
              messaging_callback_context: { 'adapter' => 'slack' })

            get project_automate_path(project, vueroute: "agent-sessions/#{foreign_workflow.id}")

            expect(response).to have_gitlab_http_status(:not_found)
          end

          it 'renders another user note-mention session (gitlab_duo_note)' do
            foreign_workflow = create(:duo_workflows_workflow, project: project, user: maintainer,
              environment: :web,
              messaging_callback_context: { 'adapter' => 'gitlab_duo_note', 'note_id' => 1 })

            get project_automate_path(project, vueroute: "agent-sessions/#{foreign_workflow.id}")

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'and the user is a guest' do
        let(:user) { guest }

        it 'renders the agents page' do
          get project_automate_agents_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'and the AI catalog is not available' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :ai_catalog).and_return(false)
        end

        it 'renders the agent sessions page' do
          get project_automate_agent_sessions_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the user is entitled but their identity is not verified' do
        before do
          stub_feature_flags(dap_require_identity_verification: true)
          allow_any_instance_of(User).to receive(:identity_verified?).and_return(false) # rubocop:disable RSpec/AnyInstanceOf -- the request reloads current_user, so a per-object stub would not apply
        end

        it 'renders the page so the verification banner can be shown' do
          get project_automate_agent_sessions_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'when duo_features_enabled setting is disabled' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
      end

      it 'returns 404' do
        get project_automate_agent_sessions_path(project)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when duo_remote_flows_enabled setting is disabled' do
      before do
        project.project_setting.update!(duo_remote_flows_enabled: false)
      end

      it 'returns 404' do
        get project_automate_agent_sessions_path(project)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when vueroute is agents' do
      it 'returns successfully' do
        get project_automate_agents_path(project)

        expect(response).to have_gitlab_http_status(:ok)
      end

      context 'when the user is not signed in and the project is public' do
        let_it_be(:project) { create(:project, :public) }

        before do
          sign_out(user)
        end

        it 'returns a 404' do
          get project_automate_agents_path(project)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when vueroute is flow-triggers' do
      context 'when user can manage ai flow triggers' do
        let(:user) { maintainer }

        it 'renders successfully' do
          get project_automate_flow_triggers_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when user cannot manage ai flow triggers' do
        it 'returns 404' do
          get project_automate_flow_triggers_path(project)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when vueroute is flows' do
      context 'when user can read flows' do
        it 'returns successfully' do
          get project_automate_flows_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when user can read foundational flows' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :ai_catalog_flows).and_return(false)
          project.project_setting.update!(duo_foundational_flows_enabled: true)
        end

        it 'returns successfully' do
          get project_automate_flows_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when user cannot read flows or foundational flows' do
        let(:user) { reporter }

        it 'returns 404' do
          get project_automate_flows_path(project)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when vueroute is mcp-servers' do
      context 'when user can read mcp servers' do
        it 'returns successfully' do
          get project_automate_mcp_servers_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when user cannot read mcp servers' do
        before do
          group.ai_settings.update!(duo_workflow_mcp_enabled: false)
        end

        it 'returns 404' do
          get project_automate_mcp_servers_path(project)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when flow-triggers are requested' do
      context 'when user is not signed in' do
        before do
          sign_out(user)
        end

        it 'redirects to sign in' do
          get project_automate_flow_triggers_path(project)

          expect(response).to redirect_to(new_user_session_path)
        end
      end

      context 'when user does not have access to project' do
        let(:other_user) { create(:user) }

        before do
          sign_in(other_user)
        end

        it 'returns 404' do
          get project_automate_flow_triggers_path(project)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end

  describe 'feature category assignment' do
    it 'returns ai_catalog_curation for the agents route' do
      controller = Projects::DuoAgentsPlatformController.new
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(vueroute: 'agents'))

      expect(controller.feature_category).to eq('ai_catalog_curation')
    end

    it 'returns ai_catalog_curation for the flows route' do
      controller = Projects::DuoAgentsPlatformController.new
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(vueroute: 'flows'))

      expect(controller.feature_category).to eq('ai_catalog_curation')
    end

    it 'returns duo_agent_platform for the triggers route' do
      controller = Projects::DuoAgentsPlatformController.new
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(vueroute: 'triggers'))

      expect(controller.feature_category).to eq('duo_agent_platform')
    end

    it 'returns duo_agent_platform for the agent-sessions route' do
      controller = Projects::DuoAgentsPlatformController.new
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(vueroute: 'agent-sessions'))

      expect(controller.feature_category).to eq('duo_agent_platform')
    end

    it 'returns ai_catalog_curation when no vueroute is set' do
      controller = Projects::DuoAgentsPlatformController.new
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))

      expect(controller.feature_category).to eq('ai_catalog_curation')
    end
  end
end
