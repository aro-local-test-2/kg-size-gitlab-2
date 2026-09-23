# frozen_string_literal: true

require 'spec_helper'

# The only feature-level coverage of Duo Agentic Chat, and deliberately the only
# place it lives.
#
# Everything observable in jsdom is covered by the frontend integration tests in
# ee/spec/frontend/integration/duo_agentic_chat/: message streaming, the
# session ID dropdown, cancel and retry, tool-call rendering, the tool approval
# card, agent and model selection, and additional context injection. Those drive
# the stream explicitly rather than racing it.
#
# What is left needs a browser and a real duo-workflow-service:
#
# - the round trip from the websocket through duo-workflow-service and the GitLab
#   API to the database, which no amount of frontend mocking can prove
# - the buttons on other pages that open the panel with a canned prompt, which
#   only exist in those pages' markup
#
# The page-entry examples used to be shared examples included into the issue, job
# and blob specs. That spread duo-workflow-service across five files and filed
# the resulting flakiness against whichever page spec included them, because
# flaky-test issues are attributed per file path. Keeping them here is what makes
# that attribution honest.
#
# Add agentic chat coverage here, or preferably under
# ee/spec/frontend/integration/duo_agentic_chat/. Do not reach for a shared
# example: that is how this grew across five files the first time. See
# https://gitlab.com/gitlab-org/gitlab/-/work_items/603605.
RSpec.describe 'Duo Chat > Agentic chat smoke test', :js, :saas, :duo_workflow_service,
  feature_category: :duo_chat,
  quarantine: {
    issue: 'https://gitlab.com/gitlab-org/quality/test-failure-issues/-/issues/44286',
    type: :flaky
  } do
  let_it_be(:group) { create(:group_with_plan, :public, plan: :premium_plan) }
  let_it_be(:user) { create(:user, :with_namespace) }

  let_it_be(:project) { create(:project, :public, :repository, namespace: group, developers: user) }

  before do
    sign_in(user)
  end

  include_context 'with duo features enabled and agentic chat available for group on SaaS'
  include_context 'with duo workflow service'

  describe 'streaming and tool calls' do
    let(:merge_request) { create(:merge_request, source_project: project) }

    it 'streams a response and persists an approved tool call', :aggregate_failures do
      visit project_merge_request_path(project, merge_request)

      open_current_thread

      # Mock responses are generated via `AIGW_USE_AGENTIC_MOCK`. Without a
      # `<response>` tag the mock replies with its own text containing "mock",
      # which cannot appear in the prompt -- so unlike an echoed token it proves
      # the agent actually streamed something back.
      send_message_and_wait_for_stream_finished!('dummy-question')

      # Scope to the second message: the first is the user's own prompt, and
      # asserting on page text alone would pass on the prompt echo.
      within_testid('chat-history') do
        expect(page).to have_css('.duo-chat-message', count: 2)
        expect(page).to have_css('.duo-chat-message:nth-child(2)', text: 'mock')
      end

      # Destroy the merge request first: the tool cannot create a duplicate.
      source_branch = merge_request.source_branch
      target_branch = merge_request.target_branch
      merge_request.destroy!

      tool_calls = [{
        name: "create_merge_request",
        args: {
          title: "New feature",
          project_id: project.id,
          source_branch: source_branch,
          target_branch: target_branch
        }
      }]
      agent_msg_1 = "<response>I should create a new entity<tool_calls>#{tool_calls.to_json}</tool_calls></response>"
      agent_msg_2 = "<response>Entity created</response>"
      send_message_and_wait_for_stream_finished!("<responses>#{agent_msg_1}#{agent_msg_2}</responses>")

      approve_tool_and_wait_for_stream_finished!

      within_testid('chat-component') do
        expect(page).to have_content('Approved')
        expect(page).to have_content('Entity created')
      end

      # The tool ran against the real API, so the record must exist.
      expect(::MergeRequest.exists?(title: "New feature", project_id: project.id)).to be(true)
    end
  end

  # The three examples below cover page buttons that open the panel with a canned
  # prompt. Each one is only reachable from its own page, which is why the setup
  # differs per example rather than being hoisted.
  describe 'opening the panel from a page action' do
    context 'with the comments summary on an issue' do
      let(:issue) { create(:issue, project: project) }

      before do
        # `stub_licensed_features` re-stubs `License.feature_available?` from
        # scratch on every call, so this one drops whatever the duo context
        # stubbed. `agentic_chat` has to be restated or the panel this button
        # opens is unlicensed and the button never renders.
        stub_licensed_features(agentic_chat: true, summarize_comments: true)

        add_on_purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
        create(:gitlab_subscription_user_add_on_assignment, user: user, add_on_purchase: add_on_purchase)
      end

      it 'summarizes the issue with the Planner agent' do
        visit project_work_item_path(project, issue)

        within(".work-item-notes") do
          # This button takes some time to appear in the work
          # item page
          expect(page).to have_button('View summary', wait: 30)
          click_button('View summary')
        end

        within_testid('content-container-subtitle') do
          planner_agent = Ai::FoundationalChatAgentsDefinitions::ITEMS.find { |a| a[:reference] == 'duo_planner' }
          expect(page).to have_content(planner_agent[:name])
        end

        within_testid('chat-history') do
          expect(page).to have_css('.duo-chat-message')
          expect(page).to have_content('Summarize the comments on this issue.')
        end
      end
    end

    context 'with a failed job' do
      let(:pipeline) { create(:ci_pipeline, project: project) }
      let(:job) { create(:ci_build, :trace_artifact, :failed, pipeline: pipeline) }

      before do
        add_on_purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
        create(:gitlab_subscription_user_add_on_assignment, user: user, add_on_purchase: add_on_purchase)
      end

      it 'troubleshoots the failure' do
        visit project_job_path(project, job)

        within_testid('rca-bar-component') do
          click_button('Troubleshoot')
        end

        within_testid('chat-history') do
          expect(page).to have_css('.duo-chat-message', count: 2, wait: 20)
          expect(page).to have_content('Troubleshoot this broken pipeline.')
          expect(page).to have_content('mock response')
        end
      end
    end

    context 'with a selection on a blob page' do
      let(:file_path) { 'file-a' }

      before do
        project.repository.commit_files(
          user,
          branch_name: project.default_branch,
          message: 'Add a file',
          actions: [{ action: :create, file_path: file_path, content: 'foobar' }]
        )
      end

      it 'explains the selected code' do
        visit project_blob_path(project, File.join(project.default_branch, file_path))

        select_element('code[data-testid="content"]')

        click_button('What does the selected code mean?')

        within_testid('chat-history') do
          expect(page).to have_css('.duo-chat-message', count: 2)
          expect(page).to have_content('Explain this code.')
          expect(page).to have_content('mock response')
        end
      end
    end
  end
end
