# frozen_string_literal: true

module Analytics
  module KnowledgeGraph
    class RequestContext < Data.define(:source_type, :session_id, :request_id, :user_agent)
      # Orbit clients send the first; Workhorse sets the second for Duo Workflow sessions.
      SESSION_ID_HEADERS = %w[X-Orbit-Session-Id X-Duo-Workflow-Session-Id].freeze
      REQUEST_ID_HEADER = 'X-Orbit-Request-Id'

      TRACE_ID_PATTERN = /\A[A-Za-z0-9._-]{1,64}\z/

      VALID_SOURCE_TYPES = [
        SourceType::FRONTEND, SourceType::DWS, SourceType::MCP,
        SourceType::CORE, SourceType::REST, SourceType::CODE_INTELLIGENCE
      ].freeze

      def self.from_request(request, source_type: nil)
        new(
          source_type: source_type,
          session_id: SESSION_ID_HEADERS.map { |header| request.headers[header] }.grep(TRACE_ID_PATTERN).first,
          request_id: request.headers[REQUEST_ID_HEADER],
          user_agent: request.user_agent
        )
      end

      def initialize(source_type: nil, session_id: nil, request_id: nil, user_agent: nil)
        super(source_type: validated_source_type(source_type), session_id: accepted_trace_id(session_id),
              request_id: accepted_trace_id(request_id), user_agent: user_agent)
      end

      private

      def accepted_trace_id(value)
        value&.slice(TRACE_ID_PATTERN)
      end

      def validated_source_type(source_type)
        return source_type if VALID_SOURCE_TYPES.include?(source_type)
        return SourceType::REST if source_type.nil?

        ::Gitlab::AppLogger.warn(
          "Invalid source_type for Orbit query: #{source_type.inspect}, falling back to 'rest'"
        )

        SourceType::REST
      end
    end
  end
end
