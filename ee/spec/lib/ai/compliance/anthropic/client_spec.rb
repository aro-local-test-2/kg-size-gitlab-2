# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::Client, feature_category: :compliance_management do
  let(:api_key) { 'sk-ant-api01-test-compliance-access-key' }
  let(:sessions_url) { 'https://api.anthropic.com/v1/compliance/apps/sessions/local' }
  let(:session_id) { 'clls_01HxKpLmNoPqRsTuVwXyZaBc' }
  let(:messages_url) { "#{sessions_url}/#{session_id}/messages" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  let(:sessions_body) do
    {
      data: [
        { type: 'compliance_local_session', id: session_id, product_surface: 'claude_code' }
      ],
      next_page: 'page_AAEfQx7mPdLkq9Rt2VwHbZk'
    }.to_json
  end

  let(:messages_body) do
    {
      session: { id: session_id },
      data: [
        { type: 'compliance_local_session_message', id: 'clsm_01J4KpLmNoPqRsTuVwXyZaBc', role: 'user' }
      ],
      next_page: nil
    }.to_json
  end

  subject(:client) { described_class.new(api_key: api_key) }

  def error_body(type, message)
    { error: { type: type, message: message } }.to_json
  end

  def captured_error
    yield
    nil
  rescue described_class::Error => e
    e
  end

  describe '#initialize' do
    it 'rejects a missing key' do
      expect { described_class.new(api_key: nil) }
        .to raise_error(described_class::MissingApiKeyError, /Compliance Access Key is required/)
    end

    it 'rejects a blank key' do
      expect { described_class.new(api_key: '  ') }.to raise_error(described_class::MissingApiKeyError)
    end
  end

  describe '#local_sessions' do
    it 'authenticates with the key in the x-api-key header' do
      stub = stub_request(:get, sessions_url)
        .with(headers: { 'x-api-key' => api_key })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions

      expect(stub).to have_been_requested
    end

    it 'caps the response body it is willing to buffer' do
      expect(Gitlab::HTTP).to receive(:get)
        .with(sessions_url, hash_including(max_bytes: described_class::MAX_RESPONSE_SIZE))
        .and_return(
          instance_double(HTTParty::Response, success?: true, parsed_response: { 'data' => [] }, headers: {})
        )

      client.local_sessions
    end

    it 'returns the session data and the next page cursor', :aggregate_failures do
      stub_request(:get, sessions_url).to_return(status: 200, body: sessions_body, headers: json_headers)

      page = client.local_sessions

      expect(page.data.first['id']).to eq(session_id)
      expect(page.next_page).to eq('page_AAEfQx7mPdLkq9Rt2VwHbZk')
    end

    it 'exposes the rate-limit budget so a caller can throttle before a 429', :aggregate_failures do
      stub_request(:get, sessions_url).to_return(
        status: 200,
        body: sessions_body,
        headers: json_headers.merge(
          'anthropic-ratelimit-requests-limit' => '600',
          'anthropic-ratelimit-requests-remaining' => '12',
          'anthropic-ratelimit-requests-reset' => '2026-07-01T00:01:00Z'
        )
      )

      rate_limit = client.local_sessions.rate_limit

      expect(rate_limit.limit).to eq(600)
      expect(rate_limit.remaining).to eq(12)
      expect(rate_limit.reset_at).to eq(Time.utc(2026, 7, 1, 0, 1, 0))
    end

    it 'leaves rate_limit nil when Anthropic sends no budget headers' do
      stub_request(:get, sessions_url).to_return(status: 200, body: sessions_body, headers: json_headers)

      expect(client.local_sessions.rate_limit).to be_nil
    end

    it 'has no session envelope, which only the messages endpoint returns' do
      stub_request(:get, sessions_url).to_return(status: 200, body: sessions_body, headers: json_headers)

      expect(client.local_sessions.session).to be_nil
    end

    it 'reports the end of the walk when next_page is null' do
      body = { data: [], next_page: nil }.to_json
      stub_request(:get, sessions_url).to_return(status: 200, body: body, headers: json_headers)

      expect(client.local_sessions.next_page).to be_nil
    end

    it 'leaves out the filters that were not given' do
      stub = stub_request(:get, sessions_url)
        .with(query: { 'limit' => '50' })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(limit: 50)

      expect(stub).to have_been_requested
    end

    it 'sends the created_at filters, limit and page cursor' do
      stub = stub_request(:get, sessions_url)
        .with(query: {
          'created_at.gte' => '2026-07-01T00:00:00Z',
          'created_at.lt' => '2026-07-02T00:00:00Z',
          'limit' => '500',
          'page' => 'page_token'
        })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(
        created_at_gte: Time.utc(2026, 7, 1),
        created_at_lt: Time.utc(2026, 7, 2),
        limit: described_class::MAX_SESSIONS_LIMIT,
        page: 'page_token'
      )

      expect(stub).to have_been_requested
    end

    it 'converts a zoned timestamp to RFC 3339 in UTC' do
      stub = stub_request(:get, sessions_url)
        .with(query: { 'created_at.gte' => '2026-07-01T05:00:00Z' })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(created_at_gte: Time.new(2026, 7, 1, 1, 0, 0, '-04:00'))

      expect(stub).to have_been_requested
    end

    it 'normalizes an offset-bearing string to UTC' do
      stub = stub_request(:get, sessions_url)
        .with(query: { 'created_at.gte' => '2026-07-01T00:00:00Z' })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(created_at_gte: '2026-07-01T04:00:00+04:00')

      expect(stub).to have_been_requested
    end

    it 'accepts a Date, which has no #utc of its own' do
      stub = stub_request(:get, sessions_url)
        .with(query: { 'created_at.gte' => Date.new(2026, 7, 1).to_time.utc.iso8601 })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(created_at_gte: Date.new(2026, 7, 1))

      expect(stub).to have_been_requested
    end

    it 'rejects a timestamp string with no UTC offset' do
      expect { client.local_sessions(created_at_gte: '2026-07-01T00:00:00') }
        .to raise_error(ArgumentError, /must carry a UTC offset/)
    end

    it 'rejects a date-only timestamp string' do
      expect { client.local_sessions(created_at_gte: '2026-07-01') }
        .to raise_error(ArgumentError, /must carry a UTC offset/)
    end

    it 'rejects a string that carries an offset but is not RFC 3339' do
      expect { client.local_sessions(created_at_gte: 'yesterday at noonZ') }
        .to raise_error(ArgumentError, /not a valid RFC 3339 timestamp/)
    end

    it 'rejects a type that is neither a string nor time-like' do
      expect { client.local_sessions(created_at_gte: 12345) }
        .to raise_error(ArgumentError, /must be a Time, Date, or RFC 3339 string/)
    end

    it 'sends updated_at.gte, the filter a poll should bound on' do
      stub = stub_request(:get, sessions_url)
        .with(query: { 'updated_at.gte' => '2026-07-01T00:00:00Z' })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(updated_at_gte: Time.utc(2026, 7, 1))

      expect(stub).to have_been_requested
    end

    it 'combines updated_at.gte with the created_at window' do
      stub = stub_request(:get, sessions_url)
        .with(query: {
          'created_at.gte' => '2026-07-01T00:00:00Z',
          'created_at.lt' => '2026-07-02T00:00:00Z',
          'updated_at.gte' => '2026-07-01T12:00:00Z'
        })
        .to_return(status: 200, body: sessions_body, headers: json_headers)

      client.local_sessions(
        created_at_gte: Time.utc(2026, 7, 1),
        created_at_lt: Time.utc(2026, 7, 2),
        updated_at_gte: Time.utc(2026, 7, 1, 12)
      )

      expect(stub).to have_been_requested
    end

    it 'rejects a limit below 1' do
      expect { client.local_sessions(limit: 0) }
        .to raise_error(ArgumentError, 'limit must be an integer between 1 and 500')
    end

    it 'rejects a limit above the endpoint maximum' do
      expect { client.local_sessions(limit: described_class::MAX_SESSIONS_LIMIT + 1) }
        .to raise_error(ArgumentError, 'limit must be an integer between 1 and 500')
    end

    it 'rejects a limit that is not an integer' do
      expect { client.local_sessions(limit: '100') }
        .to raise_error(ArgumentError, 'limit must be an integer between 1 and 500')
    end

    it 'raises when the body is not an object' do
      stub_request(:get, sessions_url).to_return(status: 200, body: '[]', headers: json_headers)

      expect { client.local_sessions }
        .to raise_error(described_class::RequestError, /unexpected body/)
    end

    it 'raises when the body is not parsable' do
      stub_request(:get, sessions_url).to_return(status: 200, body: '{invalid', headers: json_headers)

      expect { client.local_sessions }
        .to raise_error(described_class::RequestError, /unparsable body/)
    end
  end

  describe '#local_session_messages' do
    it 'requests the transcript for the given session', :aggregate_failures do
      stub = stub_request(:get, messages_url).to_return(status: 200, body: messages_body, headers: json_headers)

      page = client.local_session_messages(session_id)

      expect(stub).to have_been_requested
      expect(page.data.first['id']).to eq('clsm_01J4KpLmNoPqRsTuVwXyZaBc')
    end

    it 'sends the order, limit and page cursor' do
      stub = stub_request(:get, messages_url)
        .with(query: { 'order' => 'desc', 'limit' => '1000', 'page' => 'page_token' })
        .to_return(status: 200, body: messages_body, headers: json_headers)

      client.local_session_messages(
        session_id,
        order: 'desc',
        limit: described_class::MAX_MESSAGES_LIMIT,
        page: 'page_token'
      )

      expect(stub).to have_been_requested
    end

    it 'keeps the session envelope alongside the page', :aggregate_failures do
      body = {
        session: { id: session_id, organization_uuid: '9a1e0000-0000-0000-0000-000000000000' },
        data: [{ id: 'clsm_1' }],
        next_page: nil
      }.to_json

      stub_request(:get, messages_url).to_return(status: 200, body: body, headers: json_headers)

      page = client.local_session_messages(session_id)

      expect(page.session['id']).to eq(session_id)
      expect(page.session['organization_uuid']).to eq('9a1e0000-0000-0000-0000-000000000000')
    end

    it 'escapes the session id in the path' do
      stub = stub_request(:get, "#{sessions_url}/clls%20unexpected/messages")
        .to_return(status: 200, body: messages_body, headers: json_headers)

      client.local_session_messages('clls unexpected')

      expect(stub).to have_been_requested
    end

    it 'rejects a limit above the endpoint maximum' do
      expect { client.local_session_messages(session_id, limit: 1001) }
        .to raise_error(ArgumentError, 'limit must be an integer between 1 and 1000')
    end

    it 'rejects an unsupported order' do
      expect { client.local_session_messages(session_id, order: 'newest') }
        .to raise_error(ArgumentError, 'order must be one of: asc, desc')
    end

    it 'sends the tool truncation caps' do
      stub = stub_request(:get, messages_url)
        .with(query: { 'tool_use_input_max_bytes' => '-1', 'tool_result_max_bytes' => '50000' })
        .to_return(status: 200, body: messages_body, headers: json_headers)

      client.local_session_messages(
        session_id,
        tool_use_input_max_bytes: described_class::TOOL_BYTES_SERVER_MAX,
        tool_result_max_bytes: 50_000
      )

      expect(stub).to have_been_requested
    end

    it 'omits the caps when they are not given, letting the endpoint default apply' do
      stub = stub_request(:get, messages_url)
        .with(query: { 'order' => 'asc' })
        .to_return(status: 200, body: messages_body, headers: json_headers)

      client.local_session_messages(session_id, order: 'asc')

      expect(stub).to have_been_requested
    end

    it 'rejects a tool input cap of zero, which Anthropic does not accept' do
      expect { client.local_session_messages(session_id, tool_use_input_max_bytes: 0) }
        .to raise_error(ArgumentError, /tool_use_input_max_bytes must be -1/)
    end

    it 'rejects a tool result cap below the server-maximum sentinel' do
      expect { client.local_session_messages(session_id, tool_result_max_bytes: -2) }
        .to raise_error(ArgumentError, /tool_result_max_bytes must be -1/)
    end

    it 'rejects a non-integer tool cap' do
      expect { client.local_session_messages(session_id, tool_result_max_bytes: '10000') }
        .to raise_error(ArgumentError, /tool_result_max_bytes must be -1/)
    end

    it 'rejects a nil session id' do
      expect { client.local_session_messages(nil) }
        .to raise_error(ArgumentError, 'session_id is required')
    end

    it 'rejects a blank session id' do
      expect { client.local_session_messages('  ') }
        .to raise_error(ArgumentError, 'session_id is required')
    end
  end

  describe 'error taxonomy' do
    context 'when the key is rejected' do
      it 'raises InvalidApiKeyError on 401' do
        stub_request(:get, sessions_url).to_return(
          status: 401,
          body: error_body('authentication_error', 'The API key provided is invalid or has been revoked.'),
          headers: json_headers
        )

        expect { client.local_sessions }
          .to raise_error(described_class::InvalidApiKeyError, /401.*invalid or has been revoked/)
      end

      it 'raises InvalidApiKeyError on 403' do
        stub_request(:get, sessions_url).to_return(
          status: 403,
          body: error_body('permission_error', "Missing required scopes. Got: ['read:compliance_activities']"),
          headers: json_headers
        )

        expect { client.local_sessions }
          .to raise_error(described_class::InvalidApiKeyError, /403.*Missing required scopes/)
      end
    end

    context 'when local sessions are switched off for the Claude organization' do
      before do
        stub_request(:get, sessions_url).to_return(
          status: 404,
          body: error_body('not_found_error', 'Local sessions are not available.'),
          headers: json_headers
        )
      end

      it 'raises LocalSessionsUnavailableError' do
        expect { client.local_sessions }
          .to raise_error(described_class::LocalSessionsUnavailableError, /404.*Local sessions are not available/)
      end

      it 'keeps the reason distinct from an invalid key, which callers record separately' do
        expect(described_class::LocalSessionsUnavailableError.ancestors)
          .not_to include(described_class::InvalidApiKeyError)
      end
    end

    context 'when one session is unreachable' do
      before do
        stub_request(:get, messages_url).to_return(
          status: 404,
          body: error_body('not_found_error', 'Local session not found.'),
          headers: json_headers
        )
      end

      it 'raises SessionNotFoundError' do
        expect { client.local_session_messages(session_id) }
          .to raise_error(described_class::SessionNotFoundError, /404.*Local session not found/)
      end

      it 'keeps expected attrition distinct from a rejected request', :aggregate_failures do
        expect(described_class::SessionNotFoundError.ancestors)
          .not_to include(described_class::RequestError)
        expect(described_class::SessionNotFoundError.ancestors)
          .not_to include(described_class::LocalSessionsUnavailableError)
      end
    end

    it 'raises PageCursorExpiredError for an expired messages cursor' do
      expired = 'The page cursor has expired. Restart the walk without a page parameter; ' \
        'results will reflect the current retention boundary.'

      stub_request(:get, messages_url)
        .with(query: { 'page' => 'stale_token' })
        .to_return(status: 400, body: error_body('invalid_request_error', expired), headers: json_headers)

      expect { client.local_session_messages(session_id, page: 'stale_token') }
        .to raise_error(described_class::PageCursorExpiredError, /400.*page cursor has expired/)
    end

    it 'raises RequestError for any other 400' do
      stub_request(:get, sessions_url).to_return(
        status: 400,
        body: error_body('invalid_request_error', 'created_at.lt must be strictly after created_at.gte.'),
        headers: json_headers
      )

      expect { client.local_sessions }
        .to raise_error(described_class::RequestError, /400.*strictly after/)
    end

    it 'raises RequestError for a 409' do
      stub_request(:get, sessions_url).to_return(
        status: 409,
        body: error_body('conflict_error', 'Conflict.'),
        headers: json_headers
      )

      expect { client.local_sessions }.to raise_error(described_class::RequestError, /409/)
    end

    it 'raises RequestError for a 500 marked as not worth retrying', :aggregate_failures do
      stub = stub_request(:get, sessions_url).to_return(
        status: 500,
        body: error_body('api_error', 'Internal server error.'),
        headers: json_headers.merge('x-should-retry' => 'false')
      )

      expect { client.local_sessions }.to raise_error(described_class::RequestError, /500/)
      expect(stub).to have_been_requested.once
    end

    context 'with a request-id on the response' do
      before do
        stub_request(:get, sessions_url).to_return(
          status: 403,
          body: error_body('permission_error', 'Missing required scopes.'),
          headers: json_headers.merge('request-id' => 'req_01ABCDEF')
        )
      end

      it 'carries the request-id into the error message for support escalation' do
        expect { client.local_sessions }
          .to raise_error(described_class::InvalidApiKeyError, /request-id: req_01ABCDEF/)
      end

      it 'exposes the request-id as an attribute' do
        expect(captured_error { client.local_sessions }.request_id).to eq('req_01ABCDEF')
      end
    end

    it 'leaves request_id nil when Anthropic sends no request-id' do
      stub_request(:get, sessions_url).to_return(
        status: 409,
        body: error_body('conflict_error', 'Conflict.'),
        headers: json_headers
      )

      expect(captured_error { client.local_sessions }.request_id).to be_nil
    end

    context 'when Anthropic is temporarily unavailable' do
      before do
        allow(client).to receive(:sleep)
      end

      it 'raises TransientError for a 503' do
        stub_request(:get, sessions_url).to_return(
          status: 503,
          body: error_body('overloaded_error', 'The local-sessions index is temporarily unavailable.'),
          headers: json_headers
        )

        expect { client.local_sessions }
          .to raise_error(described_class::TransientError, /503.*temporarily unavailable/)
      end

      it 'raises RetentionOverridesUnavailableError for a retention override 503, without retrying',
        :aggregate_failures do
        stub = stub_request(:get, sessions_url).to_return(
          status: 503,
          body: error_body(
            'overloaded_error',
            'The local-sessions index cannot currently evaluate retention overrides for this page. Try again later.'
          ),
          headers: json_headers
        )

        expect { client.local_sessions }
          .to raise_error(described_class::RetentionOverridesUnavailableError, /503.*retention overrides/)
        expect(stub).to have_been_requested.once
      end

      it 'keeps a retention override failure outside the countable transient branch', :aggregate_failures do
        stub_request(:get, messages_url).to_return(
          status: 503,
          body: error_body(
            'overloaded_error',
            'The local-sessions index cannot currently evaluate retention overrides for this session.'
          ),
          headers: json_headers
        )

        expect(described_class::RetentionOverridesUnavailableError.ancestors)
          .not_to include(described_class::TransientError)
        expect { client.local_session_messages(session_id) }
          .to raise_error(described_class::RetentionOverridesUnavailableError)
      end

      context 'when a transcript page cannot be returned' do
        let(:captured_content_503) do
          {
            status: 503,
            body: error_body('overloaded_error', 'Captured content is temporarily unavailable. Try again shortly.'),
            headers: json_headers
          }
        end

        it 'raises CapturedContentUnavailableError and still retries', :aggregate_failures do
          stub = stub_request(:get, messages_url).to_return(captured_content_503)

          expect { client.local_session_messages(session_id) }
            .to raise_error(described_class::CapturedContentUnavailableError, /503.*Captured content/)
          expect(stub).to have_been_requested.times(described_class::MAX_ATTEMPTS)
        end

        it 'backs off as a transient failure but stays separately countable', :aggregate_failures do
          expect(described_class::CapturedContentUnavailableError.ancestors)
            .to include(described_class::TransientError)
          expect(described_class::RetentionOverridesUnavailableError.ancestors)
            .not_to include(described_class::CapturedContentUnavailableError)
        end

        it 'succeeds when a retry returns the page' do
          stub_request(:get, messages_url)
            .to_return(captured_content_503)
            .then.to_return(status: 200, body: messages_body, headers: json_headers)

          expect(client.local_session_messages(session_id).data.first['role']).to eq('user')
        end
      end

      it 'raises TransientError for a 500 with no x-should-retry header' do
        stub_request(:get, sessions_url).to_return(
          status: 500,
          body: error_body('api_error', 'Internal server error.'),
          headers: json_headers
        )

        expect { client.local_sessions }.to raise_error(described_class::TransientError, /500/)
      end

      it 'keeps a retryable 500 retryable even when it mentions retention overrides' do
        stub_request(:get, sessions_url).to_return(
          status: 500,
          body: error_body('api_error', 'Failed to evaluate retention overrides.'),
          headers: json_headers
        )

        expect { client.local_sessions }.to raise_error(described_class::TransientError, /500/)
      end

      it 'raises RequestError for a 400 that mentions retention overrides' do
        stub_request(:get, sessions_url).to_return(
          status: 400,
          body: error_body('invalid_request_error', 'Cannot evaluate retention overrides for that range.'),
          headers: json_headers
        )

        expect { client.local_sessions }.to raise_error(described_class::RequestError, /400/)
      end
    end

    context 'when the connection fails' do
      before do
        allow(client).to receive(:sleep)
      end

      it 'raises TransientError on a read timeout' do
        stub_request(:get, sessions_url).to_timeout

        expect { client.local_sessions }
          .to raise_error(described_class::TransientError, /timed out/)
      end

      it 'raises TransientError on a connection reset, after retrying', :aggregate_failures do
        stub_request(:get, sessions_url).to_raise(Errno::ECONNRESET)

        expect { client.local_sessions }
          .to raise_error(described_class::TransientError, /request failed/)
        expect(a_request(:get, sessions_url)).to have_been_made.times(described_class::MAX_ATTEMPTS)
      end

      it 'raises TransientError on an unresolvable host' do
        stub_request(:get, sessions_url).to_raise(SocketError)

        expect { client.local_sessions }
          .to raise_error(described_class::TransientError, /request failed/)
      end

      it 'retries a connection reset that then succeeds', :aggregate_failures do
        stub_request(:get, sessions_url)
          .to_raise(Errno::ECONNREFUSED)
          .then.to_return(status: 200, body: sessions_body, headers: json_headers)

        expect(client.local_sessions.data.first['id']).to eq(session_id)
        expect(a_request(:get, sessions_url)).to have_been_made.twice
      end

      it 'raises RequestError on a blocked URL, without retrying', :aggregate_failures do
        stub_request(:get, sessions_url).to_raise(Gitlab::HTTP::BlockedUrlError)

        expect { client.local_sessions }
          .to raise_error(described_class::RequestError, /request failed/)
        expect(a_request(:get, sessions_url)).to have_been_made.once
      end

      it 'raises RequestError when the response exceeds the size cap, without retrying', :aggregate_failures do
        stub_request(:get, sessions_url).to_raise(Gitlab::HTTP::ResponseSizeTooLarge)

        expect { client.local_sessions }
          .to raise_error(described_class::RequestError, /request failed/)
        expect(a_request(:get, sessions_url)).to have_been_made.once
      end
    end
  end

  describe 'back-off' do
    before do
      allow(client).to receive(:sleep)
    end

    def rate_limited(retry_after: nil)
      headers = json_headers
      headers = headers.merge('retry-after' => retry_after.to_s) if retry_after

      {
        status: 429,
        body: error_body('rate_limit_error', 'Compliance API rate limit of 600 requests per minute exceeded.'),
        headers: headers
      }
    end

    it 'waits for the number of seconds in retry-after and then retries', :aggregate_failures do
      stub = stub_request(:get, sessions_url)
        .to_return(rate_limited(retry_after: 5), { status: 200, body: sessions_body, headers: json_headers })

      page = client.local_sessions

      expect(client).to have_received(:sleep).with(a_value_between(5, 6.25)).once
      expect(page.data.first['id']).to eq(session_id)
      expect(stub).to have_been_requested.twice
    end

    it 'falls back to exponential back-off when retry-after is absent', :aggregate_failures do
      stub = stub_request(:get, sessions_url).to_return(rate_limited)

      expect { client.local_sessions }.to raise_error(described_class::RateLimitedError)

      expect(client).to have_received(:sleep).with(a_value_between(1, 1.25))
      expect(client).to have_received(:sleep).with(a_value_between(2, 2.5))
      expect(stub).to have_been_requested.times(described_class::MAX_ATTEMPTS)
    end

    it 'never waits less than the delay it was given' do
      stub_request(:get, sessions_url).to_return(rate_limited(retry_after: 4))

      expect { client.local_sessions }.to raise_error(described_class::RateLimitedError)

      expect(client).to have_received(:sleep).with(a_value_between(4, 5)).twice
    end

    it 'spreads the wait so workers that failed together do not retry in lockstep' do
      stub_request(:get, sessions_url).to_return(rate_limited(retry_after: 4))

      waits = []
      allow(client).to receive(:sleep) { |seconds| waits << seconds }

      20.times { captured_error { client.local_sessions } }

      expect(waits.uniq.size).to be > 1
    end

    it 'hands a long retry-after back to the caller instead of holding a worker', :aggregate_failures do
      stub = stub_request(:get, sessions_url).to_return(rate_limited(retry_after: 25))

      error = captured_error { client.local_sessions }

      expect(error).to be_a(described_class::RateLimitedError)
      expect(error.retry_after).to eq(25)
      expect(client).not_to have_received(:sleep)
      expect(stub).to have_been_requested.once
    end

    it 'exposes retry_after on a transient error when Anthropic sends one', :aggregate_failures do
      stub_request(:get, sessions_url).to_return(
        status: 503,
        body: error_body('overloaded_error', 'Try again shortly.'),
        headers: json_headers.merge('retry-after' => '4')
      )

      error = captured_error { client.local_sessions }

      expect(error).to be_a(described_class::TransientError)
      expect(error.retry_after).to eq(4)
    end

    it 'stops retrying once the attempt limit is reached', :aggregate_failures do
      stub_request(:get, sessions_url).to_return(
        status: 503,
        body: error_body('overloaded_error', 'Try again shortly.'),
        headers: json_headers
      )

      expect { client.local_sessions }.to raise_error(described_class::TransientError)

      expect(a_request(:get, sessions_url)).to have_been_made.times(described_class::MAX_ATTEMPTS)
    end
  end

  describe 'rate limiting and the auto-disable threshold' do
    before do
      allow(client).to receive(:sleep)

      stub_request(:get, sessions_url).to_return(
        status: 429,
        body: error_body('rate_limit_error', 'Rate limit exceeded.'),
        headers: json_headers
      )
    end

    # The budget is shared with the customer's other tooling, so a 429 is not a
    # failure of this integration.
    it 'raises an error a caller rescuing transient failures does not catch' do
      outcome =
        begin
          client.local_sessions
        rescue described_class::TransientError
          :counted_toward_auto_disable
        rescue described_class::RateLimitedError
          :not_counted
        end

      expect(outcome).to eq(:not_counted)
    end

    it 'keeps the rate limit error outside the transient error hierarchy', :aggregate_failures do
      expect(described_class::RateLimitedError.ancestors).not_to include(described_class::TransientError)
      expect(described_class::RateLimitedError.ancestors).to include(described_class::BackoffError)
      expect(described_class::TransientError.ancestors).to include(described_class::BackoffError)
    end
  end

  describe '#each_local_session_message_page' do
    it 'returns an enumerator when no block is given' do
      expect(client.each_local_session_message_page(session_id)).to be_an(Enumerator)
    end

    it 'passes the order and truncation caps on every page', :aggregate_failures do
      first = { session: { id: session_id }, data: [{ id: 'clsm_1' }], next_page: 'page_2' }.to_json
      second = { session: { id: session_id }, data: [{ id: 'clsm_2' }], next_page: nil }.to_json
      caps = { 'order' => 'desc', 'tool_use_input_max_bytes' => '-1', 'tool_result_max_bytes' => '-1' }

      first_request = stub_request(:get, messages_url)
        .with(query: caps)
        .to_return(status: 200, body: first, headers: json_headers)

      second_request = stub_request(:get, messages_url)
        .with(query: caps.merge('page' => 'page_2'))
        .to_return(status: 200, body: second, headers: json_headers)

      pages = client.each_local_session_message_page(
        session_id,
        order: 'desc',
        tool_use_input_max_bytes: described_class::TOOL_BYTES_SERVER_MAX,
        tool_result_max_bytes: described_class::TOOL_BYTES_SERVER_MAX
      ).to_a

      expect(first_request).to have_been_requested.once
      expect(second_request).to have_been_requested.once
      expect(pages.flat_map { |page| page.data.pluck('id') }).to eq(%w[clsm_1 clsm_2])
    end

    it 'follows next_page until it is nil', :aggregate_failures do
      first = { session: { id: session_id }, data: [{ id: 'clsm_1' }], next_page: 'page_2' }.to_json
      second = { session: { id: session_id }, data: [{ id: 'clsm_2' }], next_page: nil }.to_json

      stub_request(:get, messages_url).to_return(status: 200, body: first, headers: json_headers)
      stub_request(:get, messages_url)
        .with(query: { 'page' => 'page_2' })
        .to_return(status: 200, body: second, headers: json_headers)

      ids = client.each_local_session_message_page(session_id).flat_map { |page| page.data.pluck('id') }

      expect(ids).to eq(%w[clsm_1 clsm_2])
    end

    context 'when the cursor never advances' do
      it 'raises rather than looping on a repeated cursor', :aggregate_failures do
        body = { session: { id: session_id }, data: [{ id: 'clsm_1' }], next_page: 'page_2' }.to_json

        stub_request(:get, messages_url).to_return(status: 200, body: body, headers: json_headers)
        stub_request(:get, messages_url)
          .with(query: { 'page' => 'page_2' })
          .to_return(status: 200, body: body, headers: json_headers)

        expect { client.each_local_session_message_page(session_id).to_a }
          .to raise_error(described_class::RequestError, /does not advance/)
        expect(a_request(:get, messages_url).with(query: { 'page' => 'page_2' })).to have_been_made.once
      end

      it 'raises rather than truncating when the page cap is reached' do
        stub_const("#{described_class}::MAX_PAGES", 2)

        stub_request(:get, messages_url).to_return(
          { status: 200, body: { data: [{ id: 'clsm_1' }], next_page: 'page_2' }.to_json, headers: json_headers },
          { status: 200, body: { data: [{ id: 'clsm_2' }], next_page: 'page_3' }.to_json, headers: json_headers }
        )
        stub_request(:get, messages_url).with(query: { 'page' => 'page_2' }).to_return(
          status: 200,
          body: { data: [{ id: 'clsm_2' }], next_page: 'page_3' }.to_json,
          headers: json_headers
        )

        expect { client.each_local_session_message_page(session_id).to_a }
          .to raise_error(described_class::RequestError, /exceeded 2 pages/)
      end
    end

    context 'when the messages cursor expires part way through the walk' do
      let(:expired_message) do
        'The page cursor has expired. Restart the walk without a page parameter; ' \
          'results will reflect the current retention boundary.'
      end

      let(:first_page) do
        { session: { id: session_id }, data: [{ id: 'clsm_1' }], next_page: 'page_2' }.to_json
      end

      let(:restarted_page) do
        { session: { id: session_id }, data: [{ id: 'clsm_1' }], next_page: nil }.to_json
      end

      it 'restarts the walk without the page parameter', :aggregate_failures do
        first_request = stub_request(:get, messages_url).to_return(
          { status: 200, body: first_page, headers: json_headers },
          { status: 200, body: restarted_page, headers: json_headers }
        )

        expired_request = stub_request(:get, messages_url)
          .with(query: { 'page' => 'page_2' })
          .to_return(
            status: 400,
            body: error_body('invalid_request_error', expired_message),
            headers: json_headers
          )

        ids = client.each_local_session_message_page(session_id).flat_map { |page| page.data.pluck('id') }

        expect(first_request).to have_been_requested.twice
        expect(expired_request).to have_been_requested.once
        expect(ids).to eq(%w[clsm_1 clsm_1])
      end

      it 'gives up when the restarted walk expires again' do
        stub_request(:get, messages_url).to_return(status: 200, body: first_page, headers: json_headers)
        stub_request(:get, messages_url)
          .with(query: { 'page' => 'page_2' })
          .to_return(
            status: 400,
            body: error_body('invalid_request_error', expired_message),
            headers: json_headers
          )

        expect { client.each_local_session_message_page(session_id).to_a }
          .to raise_error(described_class::PageCursorExpiredError)
      end
    end
  end
end
