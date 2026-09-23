# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::StartDuoSessionService, feature_category: :mcp_server do
  let(:create_tool) { instance_double(Mcp::Tools::Base::ApiTool, name: :create_duo_workflow) }
  let(:tools) { [create_tool] }
  let(:service) { described_class.new(tools: tools) }

  describe '.tool_name' do
    it 'returns the agreed tool name' do
      expect(described_class.tool_name).to eq('start_duo_session')
    end
  end

  describe '#description' do
    it 'points the model at the tools that follow up on the session' do
      expect(service.description).to include('get_duo_session', 'send_duo_session_input')
    end

    it 'warns that this starts a real CI job' do
      expect(service.description).to include('CI job')
    end

    it 'does not name tools that do not exist' do
      text = [service.description, service.input_schema.to_json].join

      expect(text).not_to include('add_duo_session', 'trigger_duo_flow', 'approve_duo_agent_action')
    end
  end

  describe '#annotations' do
    it 'is a destructive write, so a client filtering destructive tools can hold it back' do
      expect(service.annotations).to eq(readOnlyHint: false, destructiveHint: true)
    end
  end

  describe '#input_schema' do
    it 'requires the project, the consumer and a goal, and rejects unknown keys' do
      schema = service.input_schema

      expect(schema[:required]).to eq(%w[project_id ai_catalog_item_consumer_id goal])
      expect(schema[:additionalProperties]).to be(false)
      expect(schema[:properties].keys).to contain_exactly(:project_id, :ai_catalog_item_consumer_id, :goal)
      expect(schema.dig(:properties, :ai_catalog_item_consumer_id, :type)).to eq('integer')
    end

    it 'hides start_workflow from the model, since the tool always forces it' do
      expect(service.input_schema[:properties]).not_to have_key(:start_workflow)
    end
  end

  describe '#execute' do
    let(:request) { instance_double(Rack::Request) }
    let(:arguments) { { project_id: '7', ai_catalog_item_consumer_id: 42, goal: 'Fix the flaky spec' } }
    let(:params) { { arguments: arguments } }

    let(:rest_body) do
      { 'id' => 99, 'status' => 'created', 'workflow_definition' => 'software_development',
        'workload' => { 'id' => 5, 'message' => nil } }
    end

    let(:rest_response) do
      Mcp::Tools::Base::Response.success([{ type: 'text', text: rest_body.to_json }], rest_body)
    end

    it 'forces start_workflow so the session actually runs' do
      expect(create_tool).to receive(:execute).with(
        request: request,
        params: { arguments: arguments.merge(start_workflow: true) }
      ).and_return(rest_response)

      service.execute(request: request, params: params)
    end

    it 'rejects arguments outside the schema, so source_type cannot be spoofed' do
      expect(create_tool).not_to receive(:execute)

      result = service.execute(
        request: request,
        params: { arguments: arguments.merge(source_type: :slack) }
      )

      expect(result[:isError]).to be(true)
      expect(result.dig(:content, 0, :text)).to include('Validation error')
    end

    it 'returns a poll hint and the session identifiers instead of the raw workflow entity' do
      allow(create_tool).to receive(:execute).and_return(rest_response)

      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]).to eq(
        'workflow_id' => 99,
        'status' => 'created',
        'workload_id' => 5,
        'poll_after_seconds' => described_class::POLL_AFTER_SECONDS
      )
      expect(result.dig(:content, 0, :text)).to include('Session 99 started', 'get_duo_session',
        'workflow_id=99', described_class::POLL_AFTER_SECONDS.to_s)
    end

    context 'when the route returns an error' do
      let(:bad_request) do
        Mcp::Tools::Base::Response.error('400 Bad request - goal is missing', { 'message' => '400 Bad request' })
      end

      it 'passes it through unchanged' do
        allow(create_tool).to receive(:execute).and_return(bad_request)

        expect(service.execute(request: request, params: params)).to eq(bad_request)
      end
    end

    context 'when required arguments are missing' do
      let(:arguments) { { project_id: '7' } }

      it 'returns a validation error without calling the route' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('Validation error')
      end
    end

    context 'when the underlying tool is not registered' do
      let(:tools) { [] }

      it 'returns a tool-not-found error' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include("start_duo_session is not available on this GitLab instance")
      end
    end
  end
end
