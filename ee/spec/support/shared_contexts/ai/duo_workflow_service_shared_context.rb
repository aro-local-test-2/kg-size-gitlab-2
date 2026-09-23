# frozen_string_literal: true

# Stands up a real duo-workflow-service and points GitLab at it.
#
# This is setup, not behaviour, which is why it stays shared: the agentic chat
# smoke test needs it, and so do specs that are not about chat at all but land on
# a page that opens the panel. The shared *examples* that used to live alongside
# it were merged into ee/spec/features/duo_chat/agentic_chat_smoke_spec.rb, so
# that agentic chat coverage is not spread across unrelated feature specs -- see
# https://gitlab.com/gitlab-org/gitlab/-/work_items/603605.
RSpec.shared_context 'with duo workflow service' do
  include AgenticChatHelpers

  let(:model_definitions) do
    {
      'models' => [
        { 'name' => 'Claude Sonnet', 'identifier' => 'claude_sonnet_4_5_20250929' },
        { 'name' => 'Claude Haiku', 'identifier' => 'claude_haiku_4_5_20251001' }
      ],
      'unit_primitives' => [
        {
          'feature_setting' => 'duo_agent_platform_agentic_chat',
          'default_model' => 'claude_sonnet_4_5_20250929',
          'selectable_models' => %w[claude_sonnet_4_5_20250929 claude_haiku_4_5_20251001],
          'beta_models' => []
        }
      ]
    }
  end

  let(:model_definitions_response) { model_definitions.to_json }

  before do
    # Write-only skips the full checkpoint row; the incremental read path is not
    # yet live, so keep it off here where the flow still reads full checkpoints.
    stub_feature_flags(duo_ui_next: false, use_generic_gitlab_api_tools: false,
      agentic_chat_flow_registry_migration: false, duo_workflow_write_incremental_only: false)

    allow_next_instance_of(::Gitlab::Llm::DuoChat) do |instance|
      allow(instance).to receive(:credits_available?).and_return(true)
    end

    stub_config(
      duo_workflow: {
        service_url: "0.0.0.0:#{Tasks::Gitlab::AiGateway::Utils.duo_workflow_service_port}",
        secure: false
      }
    )

    stub_request(:get, "https://cloud.gitlab.com/ai/v1/models%2Fdefinitions")
      .to_return(
        status: 200,
        body: model_definitions_response,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')

    # Currently this health check runs for each test case while the DWS instance runs throughout the test cases.
    # This is because the health check uses the ListToolsRequest gRPC and the request requires
    # a user instance with stub_config configured to point duo_workflow.service_url to the DWS.
    # (at the moment, a proper health check RPC is not implemented yet)
    ensure_duo_workflow_service_running!
  end
end
