# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AI Sidepanel', :js, feature_category: :duo_agent_platform do
  let_it_be_with_reload(:project) { create(:project, :repository) }
  let_it_be_with_reload(:user) { create(:user, :with_namespace) }
  let(:ai_sidepanel_selector) { 'ai-related-panels' }
  let(:sessions_toggle_selector) { 'ai-sessions-toggle' }

  before_all do
    project.add_developer(user)
    project.project_setting.update!(duo_remote_flows_enabled: true, duo_features_enabled: true)
  end

  before do
    sign_in(user)

    # These examples cover the flat session list, which is what ships while
    # duo_panel_session_inbox is off. Feature specs enable every flag by default, and the
    # flag-on inbox is covered by the frontend integration specs.
    stub_feature_flags(duo_panel_session_inbox: false)

    stub_licensed_features(ai_workflows: true)
    allow(::Ai::DuoWorkflow).to receive(:enabled?).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)

    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :read_duo_workflow, anything).and_return(true)
    allow(Ability).to receive(:allowed?).with(user, :duo_workflow, anything).and_return(true)

    allow(::Ai::AmazonQ).to receive(:enabled?).and_return(false)

    allow_next_instance_of(::Gitlab::Llm::DuoChat) do |instance|
      allow(instance).to receive_messages(
        show_duo_entry_point?: true,
        enabled_for_container?: true,
        agentic_mode_available?: true,
        classic_chat_available?: false,
        credits_available?: true,
        usage_billing_forbidden?: false,
        chat_disabled_reason: nil
      )
    end
  end

  describe 'sidepanel visibility' do
    it 'shows the AI sidepanel toggle and can expand' do
      # Enable Agentic mode so sessions toggle appears
      set_cookie('duo_agentic_mode_on', 'true')

      visit project_path(project)

      expect(page).to have_testid(ai_sidepanel_selector)

      expect(page).not_to have_content("Sessions")

      within_testid(ai_sidepanel_selector) do
        find_by_testid(sessions_toggle_selector).click
      end

      # Verify we're now in the agent sessions view
      expect(page).to have_content("Sessions")
    end
  end

  describe 'agent sessions in sidepanel' do
    let_it_be(:workflow1) do
      create(:duo_workflows_workflow,
        project: project,
        user: user,
        goal: 'Fix pipeline issues',
        workflow_definition: 'issue_to_mr',
        environment: :web)
    end

    let_it_be(:workflow2) do
      create(:duo_workflows_workflow,
        project: project,
        user: user,
        goal: 'Review code changes',
        workflow_definition: 'code_review',
        environment: :web)
    end

    before do
      # Enable Agentic mode so sessions toggle appears
      set_cookie('duo_agentic_mode_on', 'true')

      visit project_path(project)

      within_testid(ai_sidepanel_selector) do
        find_by_testid(sessions_toggle_selector).click
      end
    end

    it 'displays the sessions list' do
      expect(page).to have_content(workflow1.title)
      expect(page).to have_content(workflow2.title)
    end

    it 'shows session details in the bottom overlay' do
      expect(page).to have_selector('a[href*="/agent-sessions/"]')
      find('a[href*="/agent-sessions/"]', match: :first).click

      expect(page).to have_content('Session details')

      find_by_testid('details-overlay-toggle').click

      within_testid('details-overlay-content') do
        expect(find_by_testid('session-id')).to have_text(/\A\d+\z/)
        expect(page).to have_content('Flow')
      end

      expect(page).to have_no_content('GraphQL error:')
    end
  end

  describe 'agent sessions empty state in sidepanel' do
    before do
      Ai::DuoWorkflows::Workflow.where(project: project, user: user).delete_all

      # Enable Agentic mode so sessions toggle appears
      set_cookie('duo_agentic_mode_on', 'true')
    end

    context 'when duo features are enabled' do
      before do
        visit project_path(project)
      end

      it 'shows empty state when no sessions exist' do
        within_testid(ai_sidepanel_selector) do
          find_by_testid(sessions_toggle_selector).click
        end

        expect(page).to have_content('No agent sessions yet', wait: 10)
      end
    end

    context 'when duo features are disabled' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
        visit project_path(project)
      end

      it 'shows only the disabled toggle button' do
        within_testid(ai_sidepanel_selector) do
          expect(page).to have_testid("duo-disabled-toggle")
          expect(page).not_to have_testid("ai-chat-toggle")
          expect(page).not_to have_testid("ai-sessions-toggle")
          expect(page).not_to have_testid("ai-history-toggle")
        end
      end
    end
  end

  context 'when agentic_mode_available is false' do
    before do
      allow_next_instance_of(::Gitlab::Llm::DuoChat) do |instance|
        allow(instance).to receive_messages(
          show_duo_entry_point?: true,
          enabled_for_container?: true,
          agentic_mode_available?: false,
          classic_chat_available?: false,
          credits_available?: true,
          usage_billing_forbidden?: false,
          chat_disabled_reason: nil
        )
      end
    end

    describe 'sidepanel visibility' do
      it 'shows the AI sidepanel' do
        visit project_path(project)

        expect(page).to have_testid(ai_sidepanel_selector)
      end
    end

    describe 'sessions tab functionality' do
      let_it_be(:workflow) do
        create(:duo_workflows_workflow,
          project: project,
          user: user,
          goal: 'Test workflow',
          workflow_definition: 'issue_to_mr',
          environment: :web)
      end

      it 'can navigate to sessions and displays sessions list' do
        visit project_path(project)

        within_testid(ai_sidepanel_selector) do
          find_by_testid(sessions_toggle_selector).click
        end

        expect(page).to have_content("Sessions")
        expect(page).to have_content(workflow.title)
      end
    end

    describe 'agentic mode UI elements' do
      it 'does not show agentic mode toggle in chat' do
        visit project_path(project)

        within_testid(ai_sidepanel_selector) do
          find_by_testid('ai-chat-toggle').click
        end

        expect(page).not_to have_content('Agentic mode')
        expect(page).not_to have_content('Agentic')
      end
    end
  end
end
