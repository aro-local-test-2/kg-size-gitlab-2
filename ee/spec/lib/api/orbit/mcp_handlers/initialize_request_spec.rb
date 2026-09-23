# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Orbit::McpHandlers::InitializeRequest, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp_orbit]) }

  it 'falls back to a version it supports' do
    expect(described_class::HANDSHAKE_PROTOCOL_VERSIONS)
      .to include(described_class::LATEST_HANDSHAKE_PROTOCOL_VERSION)
  end

  describe '#invoke' do
    context 'with valid protocol version' do
      it 'returns server info with negotiated version' do
        handler = described_class.new(
          { protocolVersion: '2025-06-18' },
          access_token,
          user,
          request_context: Analytics::KnowledgeGraph::RequestContext.new(
            source_type: Analytics::KnowledgeGraph::SourceType::MCP)
        )
        result = handler.invoke

        expect(result[:protocolVersion]).to eq('2025-06-18')
        expect(result[:serverInfo][:name]).to eq('GitLab Orbit MCP Server')
        expect(result[:serverInfo][:version]).to eq(Gitlab::VERSION)
        expect(result[:capabilities][:tools][:listChanged]).to be(false)
      end

      described_class::HANDSHAKE_PROTOCOL_VERSIONS.each do |version|
        it "echoes handshake protocol version #{version}" do
          handler = described_class.new(
            { protocolVersion: version },
            access_token,
            user,
            request_context: Analytics::KnowledgeGraph::RequestContext.new(
            source_type: Analytics::KnowledgeGraph::SourceType::MCP)
          )

          expect(handler.invoke[:protocolVersion]).to eq(version)
        end
      end

      described_class::STATELESS_PROTOCOL_VERSIONS.each do |version|
        it "negotiates protocol version #{version} down to the latest handshake version" do
          handler = described_class.new(
            { protocolVersion: version },
            access_token,
            user,
            request_context: Analytics::KnowledgeGraph::RequestContext.new(
              source_type: Analytics::KnowledgeGraph::SourceType::MCP)
          )

          expect(handler.invoke[:protocolVersion]).to eq('2025-11-25')
        end
      end
    end

    context 'when protocolVersion is missing' do
      it 'raises ArgumentError' do
        handler = described_class.new({}, access_token, user,
          request_context: Analytics::KnowledgeGraph::RequestContext.new(
            source_type: Analytics::KnowledgeGraph::SourceType::MCP))

        expect { handler.invoke }.to raise_error(ArgumentError, /Missing required parameter/)
      end
    end

    context 'when protocolVersion is unsupported' do
      it 'raises ArgumentError' do
        handler = described_class.new(
          { protocolVersion: '1999-01-01' },
          access_token,
          user,
          request_context: Analytics::KnowledgeGraph::RequestContext.new(
            source_type: Analytics::KnowledgeGraph::SourceType::MCP)
        )

        expect { handler.invoke }.to raise_error(ArgumentError, /Unsupported protocol version/)
      end
    end
  end
end
