# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ServerSideExecutionService, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, :running, :agentic_chat, user: user, project: project)
  end

  let(:goal) { 'What does this project do?' }
  let(:approval) { nil }
  let(:token) { 'oauth-token-123' }
  let(:token_result) do
    ServiceResponse.success(payload: { oauth_access_token: instance_double(OauthAccessToken, plaintext_token: token) })
  end

  let(:status_code) { 200 }
  let(:response) { instance_double(HTTParty::Response, success?: status_code < 400, code: status_code) }
  let(:flow_config) { { flow_config_id: 'chat', flow_config_schema_version: nil, flow_version: '^1.0.0' } }

  subject(:service) { described_class.new(workflow: workflow, goal: goal, approval: approval) }

  # Gitlab::HTTP yields HTTParty::ResponseFragment, which carries the status code
  # alongside the bytes, and a fragment is not necessarily one action: that is
  # what most of the streaming examples are about.
  def fragment(text)
    HTTParty::ResponseFragment.new(text, instance_double(Net::HTTPResponse, code: status_code.to_s), nil)
  end

  def stub_execute_endpoint(*texts)
    stub = allow(Gitlab::HTTP).to receive(:post)
    texts.each { |text| stub = stub.and_yield(fragment(text)) }
    stub.and_return(response)
  end

  before do
    stub_const("#{described_class}::STATUS_POLL_INTERVAL", 0)

    allow_next_instance_of(Ai::DuoWorkflows::WorkflowContextGenerationService) do |context_service|
      allow(context_service).to receive(:generate_oauth_token).and_return(token_result)
    end

    allow(Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return(flow_config)

    stub_execute_endpoint
  end

  describe '#execute' do
    context 'when minting the oauth token fails' do
      let(:token_result) { ServiceResponse.error(message: 'nope') }

      it 'returns an error without calling Workhorse' do
        expect(Gitlab::HTTP).not_to receive(:post)

        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:execute_workflow_failed)
      end
    end

    context 'when the turn ends' do
      before do
        workflow.require_input!
      end

      it 'returns success with the reloaded workflow' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:workflow]).to eq(workflow)
      end

      it 'requests the server-side execution endpoint with the expected query and headers',
        :aggregate_failures do
        service.execute

        expected_url = "#{Gitlab.config.gitlab.url}/api/v4/ai/duo_workflows/workflows/#{workflow.id}/execute"

        expect(Gitlab::HTTP).to have_received(:post).with(
          expected_url,
          hash_including(
            query: {
              project_id: project.id,
              root_namespace_id: project.root_ancestor.id,
              workflow_definition: 'chat',
              environment: workflow.environment,
              client_type: described_class::CLIENT_TYPE
            },
            headers: {
              'Content-Type' => 'application/json',
              'Authorization' => "Bearer #{token}"
            },
            allow_local_requests: true,
            open_timeout: described_class::OPEN_TIMEOUT,
            read_timeout: described_class::READ_TIMEOUT,
            stream_body: true
          )
        )
      end

      it 'sends a StartWorkflowRequest body with the goal and the resolved flow config' do
        service.execute

        expect(Gitlab::HTTP).to have_received(:post) do |_url, options|
          body = Gitlab::Json::SafeParser.parse(options[:body])

          expect(body).to eq(
            'goal' => goal,
            'workflowDefinition' => 'chat',
            'clientVersion' => described_class::CLIENT_VERSION,
            'flowConfigId' => 'chat',
            'flowVersion' => '^1.0.0'
          )
        end
      end

      context 'with an approval payload' do
        let(:approval) { { 'approval' => {} } }

        it 'includes it in the request body' do
          service.execute

          expect(Gitlab::HTTP).to have_received(:post) do |_url, options|
            expect(Gitlab::Json::SafeParser.parse(options[:body])['approval']).to eq(approval)
          end
        end
      end
    end

    context 'when the workflow pauses for the user or finishes' do
      where(:transition) { %i[require_input! require_plan_approval! require_tool_call_approval! finish!] }

      with_them do
        it 'returns success' do
          workflow.public_send(transition)

          expect(service.execute).to be_success
        end
      end
    end

    context 'when the stream ends while the workflow is still running' do
      it 'polls a few times and then returns a :flow_failed error', :aggregate_failures do
        expect(workflow).to receive(:reset).exactly(described_class::STATUS_POLL_ATTEMPTS).times.and_call_original

        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:flow_failed)
      end
    end

    context 'when the workflow ended failed' do
      before do
        workflow.drop!
      end

      it 'returns a :flow_failed error without exhausting the poll attempts', :aggregate_failures do
        expect(workflow).to receive(:reset).once.and_call_original

        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:flow_failed)
      end
    end

    context 'when streaming actions back' do
      before do
        workflow.require_input!
      end

      it 'yields once per action and skips keepalive lines' do
        stub_execute_endpoint(%({"a":1}\n), "\n", %({"b":2}\n))

        expect { |block| service.execute(&block) }.to yield_control.twice
      end

      it 'yields once for an action split across fragments' do
        stub_execute_endpoint('{"a":', '1}', "\n")

        expect { |block| service.execute(&block) }.to yield_control.once
      end

      it 'yields once per action when a fragment carries several' do
        stub_execute_endpoint(%({"a":1}\n{"b":2}\n{"c":3}\n))

        expect { |block| service.execute(&block) }.to yield_control.thrice
      end

      it 'does not yield for an action that is still incomplete when the stream ends' do
        stub_execute_endpoint('{"a":')

        expect { |block| service.execute(&block) }.not_to yield_control
      end

      it 'does not require a block' do
        stub_execute_endpoint(%({"a":1}\n))

        expect(service.execute).to be_success
      end

      it 'keeps the turn going and tracks the error when the block raises', :aggregate_failures do
        stub_execute_endpoint(%({"a":1}\n{"b":2}\n))
        error = StandardError.new('slack is down')

        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id).twice

        expect(service.execute { raise error }).to be_success
      end
    end

    context 'when Workhorse rejects the request before streaming' do
      where(:status_code, :reason) do
        409 | :workflow_locked
        403 | :forbidden
        400 | :execute_workflow_failed
        502 | :execute_workflow_failed
      end

      with_them do
        it 'returns the matching error reason', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(reason)
        end

        it 'does not report an error body as progress' do
          stub_execute_endpoint(%({"message":"nope"}\n))

          expect { |block| service.execute(&block) }.not_to yield_control
        end
      end
    end

    context 'when the connection fails before anything is streamed' do
      before do
        allow(Gitlab::HTTP).to receive(:post).and_raise(Net::ReadTimeout)
      end

      it 'tracks the exception and returns an error', :aggregate_failures do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(Net::ReadTimeout),
          workflow_id: workflow.id)

        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:execute_workflow_failed)
      end
    end

    context 'when the connection fails mid-turn' do
      before do
        allow(Gitlab::HTTP).to receive(:post).and_yield(fragment(%({"a":1}\n))).and_raise(Net::ReadTimeout)
        allow(::Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'falls back to the workflow status, which owns the outcome' do
        workflow.require_input!

        expect(service.execute).to be_success
      end

      it 'reports a turn that never reached a pause as failed', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:flow_failed)
      end
    end
  end
end
