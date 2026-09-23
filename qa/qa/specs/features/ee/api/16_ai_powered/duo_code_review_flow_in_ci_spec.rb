# frozen_string_literal: true

module QA
  RSpec.describe 'Ai-powered', feature_category: :duo_agent_platform do
    describe 'Duo Code Review flow in CI' do
      let(:workload_tag) { 'gitlab--duo' }
      let(:flow_reference) { EE::Flow::FoundationalFlow::CODE_REVIEW_FLOW_REFERENCE }
      let(:review_bot) { EE::Flow::FoundationalFlow::DUO_CODE_REVIEW_BOT_USERNAME }
      let(:admin_api_client) { Runtime::User::Store.admin_api_client }
      let(:owner) { create(:user, :with_personal_access_token, api_client: admin_api_client) }
      let(:api_client) { owner.api_client }

      let(:reviewed_file) { 'dap-review.txt' }
      let(:review_summary) { 'DAP e2e smoke summary' }
      let(:review_comment) { 'DAP e2e smoke comment' }

      # The mock review script has to name the merge request IID, and it is committed to the
      # default branch before the merge request exists. A freshly created project makes the
      # merge request the project's first, and the example guards that assumption.
      let(:reviewed_merge_request_iid) { 1 }

      let(:group) do
        QA::Resource::Sandbox.fabricate_via_api! do |sandbox|
          sandbox.api_client = admin_api_client
          sandbox.path = "dap-review-group-#{SecureRandom.hex(4)}"
        end
      end

      let(:project) do
        QA::Resource::Project.fabricate_via_api! do |project|
          project.api_client = api_client
          project.group = group
          project.name = "dap-review-project-#{SecureRandom.hex(4)}"
          project.initialize_with_readme = true
          project.description = 'Duo Code Review flow CI smoke test'
        end
      end

      let(:runner) do
        # Duo Agent Platform jobs may only run on instance-wide or top-level group runners
        create(:group_runner,
          api_client: api_client,
          group: group,
          name: "dap-review-runner-#{SecureRandom.hex(4)}",
          tags: [workload_tag],
          executor: :docker)
      end

      let(:merge_request) do
        create(:merge_request,
          api_client: api_client,
          project: project,
          title: 'Add a file for Duo to review',
          description: 'Duo Code Review flow CI smoke test',
          file_name: reviewed_file,
          # Keep the diff free of <, > and & so the review prompt stays parsable as XML,
          # which the agentic mock requires. See #mock_review_instructions.
          file_content: "DAP e2e smoke\n")
      end

      # What the flow is scripted to hand back to GitLab. The comment anchors to the only
      # line of the only changed file, so the review is published as a diff comment.
      let(:review_output) do
        <<~REVIEW
          <review>
          <comment old_line="" new_line="1" file="#{reviewed_file}">
          #{review_comment}.
          </comment>
          </review>
          <comments_summary>#{review_summary}.</comments_summary>
        REVIEW
      end

      # Drives the agentic-mock Duo Workflow Service to a deterministic review. Unlike the
      # Duo Developer flow, a code review goal is validated to be a merge request IID, so the
      # mock directives cannot ride along in the goal. Custom instructions are the only field
      # the flow copies into the model prompt unescaped, so they carry the script instead.
      #
      # The mock parses the whole prompt as XML and reads only the text of the <tool_calls>
      # element, so the payload must not contain a raw <, > or &. `to_json` escapes those to
      # \uXXXX and `CGI.escapeHTML` covers the quotes, and either layer alone is enough to
      # keep the payload XML-safe.
      let(:mock_review_instructions) do
        tool_calls = CGI.escapeHTML([{
          name: 'post_duo_code_review',
          args: {
            project_id: project.id,
            merge_request_iid: reviewed_merge_request_iid,
            review_output: review_output
          }
        }].to_json)

        <<~YAML
          instructions:
            - name: DAP e2e smoke
              fileFilters:
                - "*.txt"
              instructions: |
                <response>
                Posting the canned review for the Duo Code Review e2e smoke test.
                <tool_calls>#{tool_calls}</tool_calls>
                </response>
        YAML
      end

      before do
        # Admin creates the top-level group, then grants the non-admin user Owner on it so the
        # remaining Duo Agent Platform setup runs as that Owner (api_client). Admin also assigns
        # the Owner a Duo seat, required for the create_duo_workflow entitlement gate.
        group.add_member(owner, Resource::Members::AccessLevel::OWNER)
        EE::Flow::FoundationalFlow.assign_duo_seat!(owner, api_client: admin_api_client)

        EE::Flow::FoundationalFlow.enable_on_group!(group, flow_reference: flow_reference, api_client: api_client)
        project

        # The flow reads custom instructions from the default branch, so commit them before the
        # merge request exists and nothing pushes to the target branch afterwards.
        QA::Resource::Repository::Commit.fabricate_via_api! do |commit|
          commit.api_client = api_client
          commit.project = project
          commit.commit_message = 'Add merge request review instructions'
          commit.add_files([{
            file_path: '.gitlab/duo/mr-review-instructions.yaml',
            content: mock_review_instructions
          }])
        end

        EE::Flow::FoundationalFlow.enable_remote_flows_on_project!(project, api_client: api_client)

        EE::Flow::FoundationalFlow.wait_for_flow_consumer!(group, project, flow_reference: flow_reference,
          api_client: api_client)

        runner.wait_until_online
      end

      after do
        runner&.remove_via_api!
        project&.remove_via_api!
        group&.remove_via_api!
      end

      context 'on Self-managed', :orchestrated, :duo_agent_platform, :requires_admin do
        it 'reviews a merge request through the code review flow in a CI pipeline' do
          expect(merge_request.iid).to eq(reviewed_merge_request_iid)

          EE::Flow::FoundationalFlow.request_code_review!(merge_request, api_client: api_client,
            admin_api_client: admin_api_client)

          # Poll for the flow rather than trusting the reviewer update: without Duo Agent
          # Platform routing the update still succeeds, but falls back to the non-agentic
          # review service and no flow is ever created.
          workflow = nil
          Support::Waiter.wait_until(
            message: 'Wait for the code review flow to be created',
            max_duration: 300,
            sleep_interval: 5
          ) { workflow = EE::Resource::Ai::DuoWorkflow.find_latest_in_project(project, api_client: api_client) }

          expect(workflow.workflow_definition).to eq(flow_reference)

          # Wait for the workload pipeline (source: duo_workflow) to be created, then to succeed.
          pipeline = nil
          Support::Waiter.wait_until(
            message: 'Wait for duo_workflow pipeline to be created',
            max_duration: 120,
            sleep_interval: 5
          ) { pipeline = workflow.workload_pipeline }

          Flow::Pipeline.wait_for_pipeline_to_have_status_by_id(
            project: project,
            pipeline_id: pipeline[:id],
            status: 'success',
            wait: 900
          )

          terminal_statuses = %w[finished failed stopped]
          workflow_status = nil
          Support::Waiter.wait_until(
            message: 'Wait for workflow to reach a terminal status',
            max_duration: 120,
            sleep_interval: 5
          ) { terminal_statuses.include?(workflow_status = workflow.current_status) }

          expect(workflow_status).to eq('finished'),
            "Expected the code review flow to finish, but its status was '#{workflow_status}'"

          # The flow posts its review back through the code review add_comments API. The bot
          # authors both the summary and the inline comments, so match the summary on its body
          # rather than on the author alone.
          Support::Waiter.wait_until(
            message: "Wait for #{review_bot} to post its review summary on the merge request",
            max_duration: 180,
            sleep_interval: 5
          ) do
            merge_request.notes.any? do |note|
              !note[:system] && note.dig(:author, :username) == review_bot &&
                note[:body].include?(review_summary)
            end
          end

          # Publishing the draft notes is a separate step from posting the summary, so wait
          # for the review to land on the diff as well.
          Support::Waiter.wait_until(
            message: "Wait for #{review_bot} to publish its diff note on the merge request",
            max_duration: 120,
            sleep_interval: 5
          ) do
            merge_request.notes.any? { |note| note[:type] == 'DiffNote' && note[:body].include?(review_comment) }
          end
        end
      end
    end
  end
end
