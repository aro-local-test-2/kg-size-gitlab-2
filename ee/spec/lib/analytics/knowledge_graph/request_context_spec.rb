# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Analytics::KnowledgeGraph::RequestContext, feature_category: :knowledge_graph do
  describe '.from_request' do
    def context_for(headers)
      request = double(headers: headers, user_agent: 'TestAgent/1.0') # rubocop:disable RSpec/VerifiedDoubles -- fast_spec_helper does not load ActionDispatch

      described_class.from_request(request, source_type: 'rest')
    end

    it 'reads the Orbit session and request headers' do
      context = context_for(
        'X-Orbit-Session-Id' => 'session-abc',
        'X-Orbit-Request-Id' => 'request-xyz'
      )

      expect(context.session_id).to eq('session-abc')
      expect(context.request_id).to eq('request-xyz')
      expect(context.source_type).to eq('rest')
      expect(context.user_agent).to eq('TestAgent/1.0')
    end

    it 'reads the session id Workhorse sets for Duo Workflow' do
      context = context_for('X-Duo-Workflow-Session-Id' => 'workflow-123')

      expect(context.session_id).to eq('workflow-123')
    end

    it 'prefers the Orbit session header over the Duo Workflow one' do
      context = context_for(
        'X-Orbit-Session-Id' => 'orbit-session',
        'X-Duo-Workflow-Session-Id' => 'workflow-session'
      )

      expect(context.session_id).to eq('orbit-session')
    end

    it 'uses the Duo Workflow session when the Orbit one is blank' do
      context = context_for(
        'X-Orbit-Session-Id' => '',
        'X-Duo-Workflow-Session-Id' => 'workflow-session'
      )

      expect(context.session_id).to eq('workflow-session')
    end

    it 'uses the Duo Workflow session when the Orbit one is unusable' do
      context = context_for(
        'X-Orbit-Session-Id' => 'has spaces and $ymbols',
        'X-Duo-Workflow-Session-Id' => 'workflow-session'
      )

      expect(context.session_id).to eq('workflow-session')
    end

    it 'is empty when no trace headers are sent' do
      context = context_for({})

      expect(context.session_id).to be_nil
      expect(context.request_id).to be_nil
    end

    it 'drops values that are too long or contain unexpected characters' do
      context = context_for(
        'X-Orbit-Session-Id' => 'a' * 65,
        'X-Orbit-Request-Id' => 'has spaces and $ymbols'
      )

      expect(context.session_id).to be_nil
      expect(context.request_id).to be_nil
    end

    it 'accepts the longest permitted value' do
      context = context_for('X-Orbit-Session-Id' => 'a' * 64)

      expect(context.session_id).to eq('a' * 64)
    end
  end

  describe '.new' do
    it 'keeps a source type Orbit serves' do
      context = described_class.new(source_type: Analytics::KnowledgeGraph::SourceType::CODE_INTELLIGENCE)

      expect(context.source_type).to eq(Analytics::KnowledgeGraph::SourceType::CODE_INTELLIGENCE)
    end

    it 'defaults an unset source type to rest without warning' do
      allow(Gitlab::AppLogger).to receive(:warn)

      expect(described_class.new.source_type).to eq(Analytics::KnowledgeGraph::SourceType::REST)
      expect(Gitlab::AppLogger).not_to have_received(:warn)
    end

    it 'falls back to rest and warns for a source type Orbit does not serve' do
      allow(Gitlab::AppLogger).to receive(:warn)

      context = described_class.new(source_type: 'invalid')

      expect(context.source_type).to eq(Analytics::KnowledgeGraph::SourceType::REST)
      expect(Gitlab::AppLogger).to have_received(:warn)
        .with("Invalid source_type for Orbit query: \"invalid\", falling back to 'rest'")
    end

    it 'drops trace ids that callers pass in directly' do
      context = described_class.new(session_id: 'has spaces', request_id: 'a' * 65)

      expect(context.session_id).to be_nil
      expect(context.request_id).to be_nil
    end
  end
end
