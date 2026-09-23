# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Client, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:slug) { 'my-group' }
  let(:name) { 'my-repo' }
  let(:token) { 'ar-bootstrap-token-value' }
  let(:jwt_credential) { 'fake-jwt-header-segment.fake-jwt-payload-segment.fake-jwt-signature-segment' }
  let(:current_user) { instance_double(User) }
  let(:token_exchange) { instance_double(ArtifactRegistry::TokenExchange, token_for: token) }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  let(:client) do
    described_class.new(base_url: base_url, current_user: current_user, token_exchange: token_exchange)
  end

  let(:repository_url) { "#{base_url}/api/v1/#{slug}/repositories/#{name}" }
  let(:repositories_url) { "#{base_url}/api/v1/#{slug}/repositories" }

  let(:retry_options) do
    described_class::RETRY_OPTIONS.merge(interval: 0, interval_randomness: 0, backoff_factor: 0)
  end

  let(:next_cursor) { 'eyJpZCI6MjB9' }
  let(:prev_cursor) { 'eyJpZCI6MTB9' }

  let(:repository_response) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => name,
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Maven repository',
      'artifacts_count' => 12,
      'downloads_count' => 340,
      'size_bytes' => 987_654,
      'created_at' => '2026-07-01T10:00:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'created_by' => '101',
      'updated_by' => '202'
    }
  end

  # Pinned literally: this is the single cross-repo wire contract with AR's
  # internal/auth/servicetoken HeaderName. A rename here ships green and every
  # service request is rejected by the guard, so assert the string, not the
  # constant the other examples reference.
  describe 'SERVICE_TOKEN_HEADER' do
    it { expect(described_class::SERVICE_TOKEN_HEADER).to eq('Gitlab-Artifact-Registry-Token') }
  end

  # Narrowing faraday-retry's allowlist is what keeps a replayed artifact eviction from reporting
  # AR's 404 for a delete that already succeeded. Asserted on the constant as well as through the
  # per-method request counts, so widening it back is a failing test rather than a silent regression.
  describe 'RETRY_OPTIONS' do
    it 'drops DELETE and keeps the idempotent read methods' do
      expect(described_class::RETRY_OPTIONS[:methods]).to contain_exactly(:get, :head, :options, :put)
    end
  end

  # label distinguishes invocations that share a status and body_class, which
  # the repositories list has several of. Only the repositories read reports
  # list_class, so expect_no_list_class opts a case into asserting the key is
  # absent rather than merely unchecked. Endpoints that never report it leave
  # the flag off.
  shared_examples 'rejecting an unexpected success body' do |status:, body:, body_class:, label: nil,
    list_class: nil, expect_no_list_class: false|
    it "raises UnavailableError for a #{status} carrying a #{body_class} body#{label && " (#{label})"}",
      :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_request(http_method, request_url).to_return(status: status, body: body, headers: json_headers)

      expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(described_class::UnavailableError),
        hash_including(
          { status: status, url: base_url, body_class: body_class, list_class: list_class }.compact
        )
      )

      next unless expect_no_list_class

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(described_class::UnavailableError), hash_excluding(:list_class)
      )
    end
  end

  shared_examples 'rejecting an invalid argument before any request' do
    it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
      request = stub_ar_list(body: list_response.to_json)

      expect { perform }.to raise_error(ArgumentError)
      expect(token_exchange).not_to have_received(:token_for)
      expect(request).not_to have_been_requested
    end
  end

  shared_examples 'a keyset artifact list read' do |list_segment:, nested: false|
    it 'returns an empty page for an existing repository that holds no artifacts' do
      stub_ar_list(body: [].to_json)

      expect(perform.nodes).to eq([])
    end

    context 'with the keyset query parameters' do
      it 'forwards limit and cursor' do
        request = stub_request(:get, request_url)
          .with(query: { limit: '100', cursor: 'opaque-cursor' })
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)

        perform_with(limit: 100, cursor: 'opaque-cursor')

        expect(request).to have_been_requested
      end

      it 'omits the query parameters that were not supplied, leaving the read on the contract sort' do
        stub_ar_list(body: list_response.to_json)

        perform

        expect(a_request(:get, request_url).with { |req| req.uri.query.blank? }).to have_been_made
      end
    end

    context 'when parsing the Link header for cursors' do
      it 'reads the next and prev cursors from the Link header', :aggregate_failures do
        next_url = "#{request_url}?limit=20&cursor=#{next_cursor}"
        prev_url = "#{request_url}?limit=20&cursor=#{prev_cursor}"
        stub_ar_list(
          body: list_response.to_json,
          headers: json_headers.merge('Link' => %(<#{next_url}>; rel="next", <#{prev_url}>; rel="prev"))
        )

        page = perform

        expect(page.next_cursor).to eq(next_cursor)
        expect(page.prev_cursor).to eq(prev_cursor)
      end

      it 'leaves both cursors nil when the response carries no Link header', :aggregate_failures do
        stub_ar_list(body: list_response.to_json)

        page = perform

        expect(page.next_cursor).to be_nil
        expect(page.prev_cursor).to be_nil
      end
    end

    context 'when AR returns 404' do
      it 'returns nil rather than raising' do
        stub_request(:get, request_url)
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect(perform).to be_nil
      end

      it 'returns nil even when the 404 body is empty' do
        stub_request(:get, request_url).to_return(status: 404, body: '')

        expect(perform).to be_nil
      end

      it 'logs the envelope, so a path that drifted from AR is still diagnosable' do
        stub_request(:get, request_url).to_return(
          status: 404,
          body: error_envelope(code: 'not_found', message: 'repository not found', request_id: 'req-404').to_json,
          headers: json_headers
        )

        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError),
            hash_including(url: base_url, slug: slug)) do |error, _context|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-404')
        end

        expect(perform).to be_nil
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status', :aggregate_failures do
          stub_request(:get, request_url).to_return(
            status: status,
            body: error_envelope(request_id: 'req-list-id').to_json,
            headers: json_headers
          )

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.request_id).to eq('req-list-id')
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when a transport failure occurs on the GET' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'retries the idempotent GET once and then raises UnavailableError', :aggregate_failures do
        stub_request(:get, request_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:get, request_url)).to have_been_made.times(retry_options[:max] + 1)
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{}', body_class: 'Hash'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '["oops"]', body_class: 'Array'
    end

    context 'when handling the credential' do
      it 'acquires it for the slug and attaches it as a Bearer header, never in the request URI',
        :aggregate_failures do
        request = stub_request(:get, request_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" })
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)

        perform

        expect(request).to have_been_requested
        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:get, request_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end

      context 'when the client addresses an organization' do
        let(:organization) { instance_double(Organizations::Organization) }
        let(:client) do
          described_class.new(
            base_url: base_url, current_user: current_user, organization: organization, token_exchange: token_exchange
          )
        end

        # The token is minted for the addressed organization (CachesClient passes
        # self), so the exchange must see it alongside the principal.
        it 'acquires the credential for that organization' do
          stub_request(:get, request_url).to_return(status: 200, body: list_response.to_json, headers: json_headers)

          perform

          expect(token_exchange).to have_received(:token_for).with(current_user, organization)
        end
      end

      it 'redacts a credential AR echoes in an error envelope, in both the raised and the logged error',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        echoed = "rejected: Authorization: Bearer #{jwt_credential}"
        stub_request(:get, request_url)
          .to_return(status: 503, body: error_envelope(message: echoed).to_json, headers: json_headers)

        expect { perform }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).not_to include(jwt_credential[0, 40])
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
          expect(logged.message).not_to include(jwt_credential[0, 40])
        end
      end
    end

    context 'when slug or the repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        nil        | 'my-repo'
        ''         | 'my-repo'
        '.'        | 'my-repo'
        '..'       | 'my-repo'
        'my-group' | nil
        'my-group' | ''
        'my-group' | '.'
        'my-group' | '..'
      end

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    unless nested
      context 'when the slug and repository name contain path separators' do
        let(:slug) { 'grp/x' }
        let(:name) { 'evil/segment' }

        it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
          encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{list_segment}"
          encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
            .to_return(status: 200, body: list_response.to_json, headers: json_headers)
          traversed = stub_request(:get,
            "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{list_segment}")

          perform

          expect(encoded).to have_been_requested
          expect(traversed).not_to have_been_requested
        end
      end
    end
  end

  describe '#repository' do
    subject(:result) { client.repository(slug: slug, name: name) }

    let(:perform) { result }
    let(:http_method) { :get }
    let(:request_url) { repository_url }

    context 'when AR returns 200 with a repository body' do
      it 'issues a GET to the repository detail path and returns a Repository', :aggregate_failures do
        request = stub_ar_get(status: 200, body: repository_response.to_json)

        expect(result).to be_a(ArtifactRegistry::Repository)
        expect(result.name).to eq(name)
        expect(request).to have_been_requested
      end

      it 'attaches the credential, User-Agent, and correlation id to the request', :aggregate_failures do
        correlation_id = 'correlation-abc-123'
        request = stub_request(:get, repository_url)
          .with(headers: {
            'Authorization' => "Bearer #{token}",
            'User-Agent' => "GitLab/#{Gitlab::VERSION}",
            'X-Request-Id' => correlation_id
          })
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        Labkit::Correlation::CorrelationId.use_id(correlation_id) do
          expect(result).to be_a(ArtifactRegistry::Repository)
        end

        expect(request).to have_been_requested
      end

      it 'omits the correlation id header when there is no current correlation id' do
        allow(Labkit::Correlation::CorrelationId).to receive(:current_id).and_return(nil)
        stub_ar_get(status: 200, body: repository_response.to_json)

        result

        expect(a_request(:get, repository_url).with { |req| !req.headers.key?('X-Request-Id') })
          .to have_been_made
      end

      it 'acquires the credential through the token exchange with the current user and slug' do
        stub_ar_get(status: 200, body: repository_response.to_json)

        result

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
      end

      it 'sends no include_permissions and exposes nil permissions by default, whatever the body carries',
        :aggregate_failures do
        stub_ar_get(status: 200, body: repository_response.merge('permissions' => repository_permissions).to_json)

        expect(result.permissions).to be_nil
        expect(a_request(:get, repository_url).with { |req| req.uri.query.blank? }).to have_been_made
      end
    end

    context 'with include_permissions: true' do
      subject(:result) { client.repository(slug: slug, name: name, include_permissions: true) }

      def stub_ar_get_with_permissions(body)
        stub_request(:get, repository_url)
          .with(query: { include_permissions: 'true' })
          .to_return(status: 200, body: body.to_json, headers: json_headers)
      end

      it 'sends include_permissions=true and exposes the repository verdicts, stamped with the read and slug',
        :aggregate_failures do
        request = stub_ar_get_with_permissions(repository_response.merge('permissions' => repository_permissions))

        permissions = result.permissions

        expect(request).to have_been_requested
        expect(permissions).to be_a(ArtifactRegistry::Permissions::Verdicts)
        expect(permissions).to be_complete
        expect(permissions.allowed?('update_repository')).to be(true)
        expect(permissions.allowed?('delete_repository')).to be(false)
        expect(permissions.read).to eq(:repository)
        expect(permissions.slug).to eq(slug)
      end

      it 'drops an action the repository set does not name and reports a missing one as incomplete',
        :aggregate_failures do
        served = repository_permissions.except('delete_artifact').merge('publish_repository' => true)
        stub_ar_get_with_permissions(repository_response.merge('permissions' => served))

        permissions = result.permissions

        expect(permissions).not_to be_complete
        expect(permissions.missing_actions).to eq(%w[delete_artifact])
        expect(permissions.allowed?('publish_repository')).to be(false)
      end

      it 'exposes an absent verdict carrying the read and slug when the body has no permissions object',
        :aggregate_failures do
        stub_ar_get_with_permissions(repository_response)

        permissions = result.permissions

        expect(permissions).to be_absent
        expect(permissions.read).to eq(:repository)
        expect(permissions.slug).to eq(slug)
        expect(result.name).to eq(name)
      end

      it 'treats a permissions value that is not an object as absent' do
        stub_ar_get_with_permissions(repository_response.merge('permissions' => [true]))

        expect(result.permissions).to be_absent
      end
    end

    context 'when AR returns 404' do
      it 'returns nil' do
        stub_ar_get(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(result).to be_nil
      end

      it 'returns nil even when the 404 body is empty' do
        stub_ar_get(status: 404, body: '')

        expect(result).to be_nil
      end

      it 'returns nil even when the 404 body is malformed' do
        stub_ar_get(status: 404, body: 'bleh')

        expect(result).to be_nil
      end
    end

    context 'when AR returns 204 on a body-expecting call' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
    end

    context 'when no base_url is supplied' do
      let(:client) { described_class.new(current_user: current_user, token_exchange: token_exchange) }
      let(:configured_url) { 'https://ar-from-config.example.test' }

      before do
        stub_config(artifact_registry: { api_url: configured_url })
      end

      it 'issues the request against the configured api_url' do
        request = stub_request(:get, "#{configured_url}/api/v1/#{slug}/repositories/#{name}")
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        result

        expect(request).to have_been_requested
      end
    end

    context 'when base_url is blank and no api_url is configured' do
      before do
        stub_config(artifact_registry: { api_url: nil })
      end

      it 'raises ConfigurationError at construction' do
        expect do
          described_class.new(current_user: current_user, token_exchange: token_exchange)
        end.to raise_error(described_class::ConfigurationError, /base_url is required/)
      end
    end

    context 'when base_url has no http(s) scheme' do
      it 'raises ConfigurationError at construction so a config typo cannot escape the typed errors',
        :aggregate_failures do
        ['localhost:8080', 'artifact-registry.example.test', 'ftp://artifact-registry.example.test'].each do |value|
          expect do
            described_class.new(base_url: value, current_user: current_user, token_exchange: token_exchange)
          end.to raise_error(described_class::ConfigurationError, /base_url must be an http\(s\) URL/)
        end
      end
    end

    describe 'ConfigurationError' do
      it 'is a client Error outside the ArgumentError hierarchy', :aggregate_failures do
        expect(described_class::ConfigurationError.ancestors).to include(described_class::Error)
        expect(described_class::ConfigurationError.ancestors).not_to include(ArgumentError)
      end
    end

    context 'when the functional default mints no credential (a non-User principal)' do
      let(:client) { described_class.new(base_url: base_url, current_user: current_user) }

      it 'raises AuthorizationError without issuing a request', :aggregate_failures do
        request = stub_ar_get(status: 200, body: repository_response.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError, /no Artifact Registry credential/i)
        expect(request).not_to have_been_requested
      end
    end

    context 'when the token exchange is explicitly nil' do
      let(:client) { described_class.new(base_url: base_url, current_user: current_user, token_exchange: nil) }

      it 'falls back to the fail-closed default instead of crashing on the nil call', :aggregate_failures do
        request = stub_ar_get(status: 200, body: repository_response.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError, /no Artifact Registry credential/i)
        expect(request).not_to have_been_requested
      end
    end

    context 'when slug or name is blank' do
      where(:slug, :name) do
        ''         | 'my-repo'
        nil        | 'my-repo'
        'my-group' | ''
        'my-group' | nil
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_ar_get(status: 200, body: repository_response.to_json)

          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug and name contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:get, "#{base_url}/api/v1/grp%2Fx/repositories/evil%2Fsegment")
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)
        traversed = stub_request(:get, "#{base_url}/api/v1/grp/x/repositories/evil/segment")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when a segment contains dot-segment traversal sequences' do
      let(:slug) { 'my-group' }
      let(:name) { '../../secret' }

      it 'escapes the separators so the value stays a single path segment', :aggregate_failures do
        encoded = stub_request(:get, "#{base_url}/api/v1/my-group/repositories/..%2F..%2Fsecret")
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)
        traversed = stub_request(:get, "#{base_url}/api/v1/secret")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when a whole path segment is a bare dot-segment (`.` or `..`)' do
      where(:slug, :name) do
        '..'       | 'my-repo'
        '.'        | 'my-repo'
        'my-group' | '..'
        'my-group' | '.'
      end

      with_them do
        it 'rejects the segment without contacting the token exchange or AR', :aggregate_failures do
          request = stub_ar_get(status: 200, body: repository_response.to_json)

          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when a success response body is absent or unparseable' do
      it 'raises UnavailableError for an empty 200 body' do
        stub_ar_get(status: 200, body: '')

        expect { result }.to raise_error(described_class::UnavailableError)
      end

      it 'raises UnavailableError for an unparseable 200 body' do
        stub_request(:get, repository_url)
          .to_return(status: 200, body: 'this-is-not-json', headers: json_headers)

        expect { result }.to raise_error(described_class::UnavailableError)
      end

      it 'raises UnavailableError for a non-object JSON 200 body' do
        stub_request(:get, repository_url)
          .to_return(status: 200, body: [].to_json, headers: json_headers)

        expect { result }.to raise_error(described_class::UnavailableError)
      end

      it 'raises UnavailableError for valid JSON sent with a non-JSON content-type' do
        stub_request(:get, repository_url)
          .to_return(status: 200, body: repository_response.to_json, headers: { 'Content-Type' => 'text/plain' })

        expect { result }.to raise_error(described_class::UnavailableError)
      end

      it 'logs the malformed response so it is distinguishable from a transport outage' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_get(status: 200, body: '')

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        502 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
        409 | ArtifactRegistry::Client::ApiError
        422 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status', :aggregate_failures do
          stub_ar_get(status: status, body: error_envelope(request_id: 'req-mapped-id').to_json)

          expect { result }.to raise_error(error_class) do |error|
            expect(error.request_id).to eq('req-mapped-id')
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when AR returns a 400 with an error envelope' do
      it 'raises ApiError carrying the status, code, message, and request_id', :aggregate_failures do
        body = { error: { code: 'bad_request', message: 'name is invalid', request_id: 'req-400' } }
        stub_ar_get(status: 400, body: body.to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.code).to eq('bad_request')
          expect(error.message).to include('name is invalid')
          expect(error.request_id).to eq('req-400')
        end
      end

      it 'redacts a credential echoed inside the envelope message and caps its length', :aggregate_failures do
        echoed = "Request rejected: Authorization: Bearer #{jwt_credential} #{'x' * 500}"
        body = { error: { code: 'bad_request', message: echoed, request_id: 'req-400' } }
        stub_ar_get(status: 400, body: body.to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.message).not_to include(jwt_credential[0, 40])
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message.length).to eq(ArtifactRegistry::ErrorReporter::MAX_SNIPPET)
          expect(error.request_id).to eq('req-400')
        end
      end

      it 'redacts a credential echoed inside the envelope code and request_id', :aggregate_failures do
        body = { error: { code: "Bearer #{jwt_credential}", message: 'rejected', request_id: jwt_credential } }
        stub_ar_get(status: 400, body: body.to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.code).to eq('Bearer [REDACTED]')
          expect(error.request_id).to eq('[REDACTED]')
        end
      end
    end

    context 'when a mapped error response has no usable error envelope' do
      it 'raises the mapped error with a nil request_id when the body has no error object', :aggregate_failures do
        stub_ar_get(status: 401, body: { detail: 'nope' }.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError) do |error|
          expect(error.request_id).to be_nil
        end
      end

      it 'keeps a String error field as the message and raises ApiError with a nil code', :aggregate_failures do
        stub_ar_get(status: 400, body: { error: 'boom' }.to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.code).to be_nil
          expect(error.message).to eq('boom')
        end
      end

      it 'raises the mapped error when the error body is empty', :aggregate_failures do
        stub_ar_get(status: 422, body: '')

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(422)
        end
      end

      it 'omits an error object whose keys all fall outside the snippet allowlist', :aggregate_failures do
        stub_ar_get(status: 422, body: { errors: { name: ['taken'] } }.to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(422)
          expect(error.code).to be_nil
          # A nil message renders as the exception class name, so the body contributed nothing.
          expect(error.message).to eq(described_class::ApiError.name)
        end
      end

      context 'when an unrecognized JSON error object carries an allowlisted key' do
        where(:allowlisted_key) { %w[detail message title] }

        with_them do
          it 'snippets that value into the message' do
            stub_ar_get(status: 403, body: { allowlisted_key => 'the request was rejected' }.to_json)

            expect { result }.to raise_error(described_class::AuthorizationError, 'the request was rejected')
          end
        end
      end

      it 'keeps a credential carried under a non-allowlisted key out of the message' do
        body = { detail: 'rejected', upstream_api_key: 'sk_live_0123456789abcdef' } # gitleaks:allow
        stub_ar_get(status: 401, body: body.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError, 'rejected')
      end

      it 'omits a non-String value under an allowlisted key, so a nested credential cannot reach the message' do
        body = { detail: { upstream_api_key: 'sk_live_0123456789abcdef' } } # gitleaks:allow
        stub_ar_get(status: 401, body: body.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError) do |error|
          expect(error.message).to eq(described_class::AuthorizationError.name)
        end
      end

      it 'redacts a credential carried in an unrecognized JSON error object', :aggregate_failures do
        stub_ar_get(status: 401, body: { detail: "rejected Bearer #{jwt_credential}" }.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError) do |error|
          expect(error.message).not_to include(jwt_credential)
          expect(error.message).to include('Bearer [REDACTED]')
        end
      end

      it 'caps an unrecognized JSON error object at the snippet limit' do
        stub_ar_get(status: 401, body: { detail: 'x' * 500 }.to_json)

        expect { result }.to raise_error(described_class::AuthorizationError) do |error|
          expect(error.message.length).to eq(ArtifactRegistry::ErrorReporter::MAX_SNIPPET)
        end
      end

      it 'snippets a non-JSON error body into the message and caps it at the snippet limit',
        :aggregate_failures do
        html_body = "<html><body>#{'x' * 500}</body></html>"
        stub_request(:get, repository_url)
          .to_return(status: 500, body: html_body, headers: { 'Content-Type' => 'text/html' })

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message.length).to eq(ArtifactRegistry::ErrorReporter::MAX_SNIPPET)
          expect(error.message).to start_with('<html>')
        end
      end

      it 'redacts an echoed Authorization header from the snippet', :aggregate_failures do
        echoed_body = "Request rejected: Authorization: Bearer #{jwt_credential} (invalid)"
        stub_request(:get, repository_url)
          .to_return(status: 400, body: echoed_body, headers: { 'Content-Type' => 'text/plain' })

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.message).not_to include(jwt_credential)
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).to start_with('Request rejected:')
        end
      end

      it 'redacts a bare JWT-shaped string from the snippet', :aggregate_failures do
        stub_request(:get, repository_url)
          .to_return(status: 400, body: "token #{jwt_credential} was rejected",
            headers: { 'Content-Type' => 'text/plain' })

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.message).not_to include(jwt_credential)
          expect(error.message).to eq('token [REDACTED] was rejected')
        end
      end

      it 'redacts before truncating, so a long body cannot leak a credential prefix' do
        stub_request(:get, repository_url)
          .to_return(status: 400, body: "Bearer #{jwt_credential} #{'x' * 500}",
            headers: { 'Content-Type' => 'text/plain' })

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.message).not_to include(jwt_credential[0, 40])
        end
      end

      it 'leaves a snippet carrying no credential untouched' do
        stub_request(:get, repository_url)
          .to_return(status: 400, body: 'repository name is invalid',
            headers: { 'Content-Type' => 'text/plain' })

        expect { result }.to raise_error(described_class::ApiError, 'repository name is invalid')
      end
    end

    context 'when an error status carries an unreadable JSON body' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        500 | ArtifactRegistry::Client::UnavailableError
      end

      with_them do
        it 'classifies the failure by its HTTP status and keeps the status on the error', :aggregate_failures do
          stub_ar_get(status: status, body: 'not json')

          expect { result }.to raise_error(error_class) do |error|
            expect(error.status).to eq(status)
            expect(error.message).to match(/unreadable response/)
          end
        end
      end
    end

    context 'when AR returns a redirect' do
      it 'surfaces the 3xx as a typed error and never contacts the Location host', :aggregate_failures do
        redirect_target = 'https://elsewhere.example.test/steal'
        stub_request(:get, repository_url)
          .to_return(status: 302, headers: { 'Location' => redirect_target })
        target = stub_request(:get, redirect_target)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(302)
        end
        expect(target).not_to have_been_requested
      end
    end

    context 'when a transport failure occurs on the GET' do
      before do
        stub_request(:get, repository_url).to_timeout
      end

      it 'retries the idempotent GET once and then raises UnavailableError', :aggregate_failures do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:get, repository_url)).to have_been_made.times(retry_options[:max] + 1)
      end

      it 'logs each transport exception without leaking the credential', :aggregate_failures do
        logged = []
        allow(Gitlab::ErrorTracking).to receive(:log_exception) { |*args| logged << args }
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)

        expect { result }.to raise_error(described_class::UnavailableError)
        # max + 1 sanitized per-attempt reports plus one terminal delivery attempt.
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).exactly(retry_options[:max] + 2).times
        expect(logged.to_s).not_to include(token)
      end
    end

    context 'when the GET fails with a connection error' do
      it 'retries a connection failure and then raises UnavailableError', :aggregate_failures do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
        stub_request(:get, repository_url).to_raise(Faraday::ConnectionFailed)

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:get, repository_url)).to have_been_made.times(retry_options[:max] + 1)
      end
    end

    context 'when the GET fails with a TLS error' do
      before do
        stub_request(:get, repository_url).to_raise(Faraday::SSLError.new('certificate verify failed'))
      end

      it 'raises UnavailableError with a TLS-specific message and does not retry', :aggregate_failures do
        expect { result }.to raise_error(
          described_class::UnavailableError, /TLS connection failed.*certificate verify failed/
        )
        expect(a_request(:get, repository_url)).to have_been_made.once
      end
    end

    context 'when AR returns a 5xx status' do
      it 'raises UnavailableError without retrying', :aggregate_failures do
        request = stub_ar_get(status: 503, body: error_envelope(code: 'service_unavailable').to_json)

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(request).to have_been_requested.once
      end

      it 'logs the server-side failure with its request context, status, and request id', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_get(status: 503, body: error_envelope(request_id: 'req-5xx').to_json)

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::UnavailableError),
          hash_including(url: base_url, method: :get, status: 503, request_id: 'req-5xx', slug: slug)
        )
      end
    end
  end

  describe '#namespace_details' do
    subject(:result) { client.namespace_details(slug: slug) }

    let(:namespace_details_url) { "#{base_url}/api/v1/#{slug}/namespace" }
    let(:namespace_details_response) { { 'slug' => slug, 'created_at' => '2026-07-01T10:00:00Z' } }

    def stub_namespace_details_get(status:, body: '', query: nil)
      stub = stub_request(:get, namespace_details_url)
      stub = stub.with(query: query) if query

      stub.to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR returns 200 with a namespace body' do
      it 'issues a GET to the per-user namespace path and returns a NamespaceDetails', :aggregate_failures do
        request = stub_namespace_details_get(status: 200, body: namespace_details_response.to_json)

        expect(result).to be_a(ArtifactRegistry::NamespaceDetails)
        expect(result.slug).to eq(slug)
        expect(result.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
        expect(request).to have_been_requested
      end

      it 'acquires the credential for the current user and attaches it as a Bearer header, no service header',
        :aggregate_failures do
        stub_namespace_details_get(status: 200, body: namespace_details_response.to_json)

        result

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:get, namespace_details_url).with(headers: { 'Authorization' => "Bearer #{token}" }))
          .to have_been_made
        expect(
          a_request(:get, namespace_details_url)
            .with { |req| req.headers.key?(described_class::SERVICE_TOKEN_HEADER) }
        ).not_to have_been_made
      end

      it 'sends no include_permissions and exposes nil permissions by default, whatever the body carries',
        :aggregate_failures do
        stub_namespace_details_get(
          status: 200, body: namespace_details_response.merge('permissions' => namespace_permissions).to_json
        )

        expect(result.permissions).to be_nil
        expect(a_request(:get, namespace_details_url).with { |req| req.uri.query.blank? }).to have_been_made
      end
    end

    context 'with include_permissions: true' do
      subject(:result) { client.namespace_details(slug: slug, include_permissions: true) }

      def stub_namespace_details_with_permissions(body)
        stub_namespace_details_get(status: 200, body: body.to_json, query: { include_permissions: 'true' })
      end

      it 'sends include_permissions=true and exposes the namespace verdicts, stamped with the read and slug',
        :aggregate_failures do
        request = stub_namespace_details_with_permissions(
          namespace_details_response.merge('permissions' => namespace_permissions)
        )

        permissions = result.permissions

        expect(request).to have_been_requested
        expect(permissions).to be_a(ArtifactRegistry::Permissions::Verdicts)
        expect(permissions).to be_complete
        expect(permissions.allowed?('create_repository')).to be(true)
        expect(permissions.allowed?('delete_repository')).to be(false)
        expect(permissions.allowed?('read_artifact')).to be(false)
        expect(permissions.read).to eq(:namespace_details)
        expect(permissions.slug).to eq(slug)
      end

      it 'drops an action the namespace set does not name and reports a missing one as incomplete',
        :aggregate_failures do
        served = namespace_permissions.except('create_repository').merge('read_artifact' => true)
        stub_namespace_details_with_permissions(namespace_details_response.merge('permissions' => served))

        permissions = result.permissions

        expect(permissions).not_to be_complete
        expect(permissions.missing_actions).to eq(%w[create_repository])
        expect(permissions.allowed?('read_artifact')).to be(false)
      end

      it 'exposes an absent verdict carrying the read and slug when the body has no permissions object',
        :aggregate_failures do
        stub_namespace_details_with_permissions(namespace_details_response)

        permissions = result.permissions

        expect(permissions).to be_absent
        expect(permissions.read).to eq(:namespace_details)
        expect(permissions.slug).to eq(slug)
        expect(result.slug).to eq(slug)
      end

      it 'treats a permissions value that is not an object as absent' do
        stub_namespace_details_with_permissions(namespace_details_response.merge('permissions' => [true]))

        expect(result.permissions).to be_absent
      end
    end

    context 'when AR returns 404 (the slug did not resolve to a namespace)' do
      before do
        stub_namespace_details_get(
          status: 404,
          body: error_envelope(code: 'not_found', message: 'namespace not found', request_id: 'req-404').to_json
        )
      end

      it 'returns nil rather than raising' do
        expect(result).to be_nil
      end

      it 'logs the envelope, so a slug that drifted from AR is still diagnosable' do
        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError),
            hash_including(url: base_url, slug: slug)) do |error, _context|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-404')
        end

        result
      end

      it 'returns nil even when the 404 body is empty' do
        stub_namespace_details_get(status: 404)

        expect(result).to be_nil
      end
    end

    context 'when AR returns 204 on a body-expecting call' do
      let(:perform) { result }
      let(:http_method) { :get }
      let(:request_url) { namespace_details_url }

      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
    end

    context 'when the slug contains path separators' do
      let(:slug) { 'grp/x' }

      it 'percent-encodes the slug segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:get, "#{base_url}/api/v1/grp%2Fx/namespace")
          .to_return(status: 200, body: namespace_details_response.to_json, headers: json_headers)
        traversed = stub_request(:get, "#{base_url}/api/v1/grp/x/namespace")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when AR returns 200 with a hollow body' do
      # Deliberate: consumers fail closed on absent verdicts, so a hollow body is a present object
      # with nil readers, not a raise. Pinned so a later reviewer does not "correct" it to raise.
      it 'returns a present NamespaceDetails whose readers are nil', :aggregate_failures do
        stub_namespace_details_get(status: 200, body: '{}')

        expect(result).to be_a(ArtifactRegistry::NamespaceDetails)
        expect(result.slug).to be_nil
        expect(result.created_at).to be_nil
        expect(result.permissions).to be_nil
      end
    end

    context 'when the slug is blank' do
      let(:slug) { '' }

      it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
        request = stub_request(:get, "#{base_url}/api/v1//namespace")

        expect { result }.to raise_error(ArgumentError)
        expect(token_exchange).not_to have_received(:token_for)
        expect(request).not_to have_been_requested
      end
    end
  end

  describe '#repositories' do
    let(:perform) { client.repositories(slug: slug) }
    let(:http_method) { :get }
    let(:request_url) { repositories_url }

    let(:other_repository_response) do
      repository_response.merge(
        'id' => 'b2c3d4e5-0000-0000-0000-000000000000',
        'name' => 'other-repo',
        'created_by' => '303',
        'updated_by' => '404'
      )
    end

    let(:repositories_body) do
      { 'repositories' => [repository_response, other_repository_response] }.to_json
    end

    let(:repositories_body_with_permissions) do
      {
        'permissions' => namespace_permissions,
        'repositories' => [
          repository_response.merge('permissions' => repository_permissions),
          other_repository_response.merge('permissions' => repository_permissions.merge('delete_repository' => true))
        ]
      }
    end

    context 'when AR returns a 200 with a page of repositories' do
      it 'parses the repositories into Repository value objects on the page', :aggregate_failures do
        request = stub_ar_list(body: repositories_body)
        page = client.repositories(slug: slug)

        expect(request).to have_been_requested
        expect(page.nodes).to all(be_a(ArtifactRegistry::Repository))
        expect(page.nodes.map(&:name)).to eq(%w[my-repo other-repo])
      end

      it 'returns an empty page when the repositories array is empty' do
        stub_ar_list(body: { 'repositories' => [] }.to_json)

        expect(client.repositories(slug: slug).nodes).to eq([])
      end

      it 'resolves a populated page from a single request with no per-element follow-up', :aggregate_failures do
        list = stub_ar_list(body: repositories_body)
        detail = stub_request(:get, "#{base_url}/api/v1/#{slug}/repositories/my-repo")

        client.repositories(slug: slug)

        expect(list).to have_been_requested.once
        expect(detail).not_to have_been_requested
      end

      it 'passes created_by and updated_by through as the raw opaque strings', :aggregate_failures do
        stub_ar_list(body: repositories_body)
        first = client.repositories(slug: slug).nodes.first

        expect(first.created_by).to eq('101')
        expect(first.updated_by).to eq('202')
      end

      it 'sends no include_permissions and exposes nil permissions by default, whatever the envelope carries',
        :aggregate_failures do
        stub_ar_list(body: repositories_body_with_permissions.to_json)

        page = client.repositories(slug: slug)

        expect(a_request(:get, repositories_url).with { |req| req.uri.query.blank? }).to have_been_made
        expect(page.permissions).to be_nil
        expect(page.nodes.map(&:permissions)).to all(be_nil)
      end
    end

    context 'with include_permissions: true' do
      def stub_ar_list_with_permissions(body, query: { include_permissions: 'true' })
        stub_request(:get, repositories_url)
          .with(query: query)
          .to_return(status: 200, body: body.to_json, headers: json_headers)
      end

      it 'sends include_permissions=true alongside the other query parameters' do
        request = stub_ar_list_with_permissions(repositories_body_with_permissions,
          query: { format: 'maven', limit: '50', include_permissions: 'true' })

        client.repositories(slug: slug, format: 'maven', limit: 50, include_permissions: true)

        expect(request).to have_been_requested
      end

      it 'exposes the envelope namespace verdicts on the page and each row its own repository verdicts',
        :aggregate_failures do
        stub_ar_list_with_permissions(repositories_body_with_permissions)

        page = client.repositories(slug: slug, include_permissions: true)

        expect(page.permissions).to be_a(ArtifactRegistry::Permissions::Verdicts)
        expect(page.permissions).to be_complete
        expect(page.permissions.allowed?('create_repository')).to be(true)
        expect(page.permissions.allowed?('read_artifact')).to be(false)
        expect(page.permissions.read).to eq(:repositories)
        expect(page.permissions.slug).to eq(slug)

        expect(page.nodes.map(&:name)).to eq(%w[my-repo other-repo])
        expect(page.nodes.first.visibility).to eq('private')
        expect(page.nodes.map { |row| row.permissions.allowed?('delete_repository') }).to eq([false, true])
        expect(page.nodes.map { |row| row.permissions.allowed?('create_repository') }).to all(be(false))
        expect(page.nodes.map { |row| row.permissions.read }).to all(eq(:repositories))
        expect(page.nodes.map { |row| row.permissions.slug }).to all(eq(slug))
      end

      it 'exposes absent verdicts carrying the read and slug when the envelope and its rows have none',
        :aggregate_failures do
        stub_ar_list_with_permissions({ 'repositories' => [repository_response] })

        page = client.repositories(slug: slug, include_permissions: true)

        expect(page.permissions).to be_absent
        expect(page.permissions.read).to eq(:repositories)
        expect(page.permissions.slug).to eq(slug)
        expect(page.nodes.first.permissions).to be_absent
        expect(page.nodes.first.permissions.read).to eq(:repositories)
        expect(page.nodes.first.name).to eq(name)
      end

      it 'exposes the envelope verdicts as incomplete when an action of the namespace set is missing' do
        served = namespace_permissions.except('create_repository')
        stub_ar_list_with_permissions(repositories_body_with_permissions.merge('permissions' => served))

        page = client.repositories(slug: slug, include_permissions: true)

        expect(page.permissions.missing_actions).to eq(%w[create_repository])
      end
    end

    context 'with query parameters' do
      it 'forwards format, kind, sort, order, limit, and cursor as query parameters' do
        request = stub_request(:get, repositories_url)
          .with(query: {
            format: 'maven', kind: 'hosted', sort: 'name', order: 'asc', limit: '50', cursor: 'opaque-cursor'
          })
          .to_return(status: 200, body: repositories_body, headers: json_headers)

        client.repositories(
          slug: slug, format: 'maven', kind: 'hosted', sort: 'name', order: 'asc', limit: 50, cursor: 'opaque-cursor'
        )

        expect(request).to have_been_requested
      end

      it 'omits the query parameters that were not supplied' do
        stub_ar_list(body: repositories_body)

        client.repositories(slug: slug)

        expect(a_request(:get, repositories_url).with { |req| req.uri.query.blank? }).to have_been_made
      end

      it 'sends a single-valued format and kind as one unbracketed parameter each' do
        request = stub_query_string('format=maven&kind=hosted&limit=50')

        client.repositories(slug: slug, format: 'maven', kind: 'hosted', limit: 50)

        expect(request).to have_been_requested
      end

      context 'with list-valued filters' do
        around do |example|
          notation = WebMock::Config.instance.query_values_notation
          WebMock::Config.instance.query_values_notation = :flat_array
          example.run
        ensure
          WebMock::Config.instance.query_values_notation = notation
        end

        it 'repeats format and kind once per value, rather than bracketing the key' do
          request = stub_query_string('format=docker&format=oci&kind=hosted&kind=remote&limit=50')

          client.repositories(slug: slug, format: %w[docker oci], kind: %w[hosted remote], limit: 50)

          expect(request).to have_been_requested
        end
      end

      def stub_query_string(query_string)
        stub_request(:get, "#{repositories_url}?#{query_string}")
          .to_return(status: 200, body: repositories_body, headers: json_headers)
      end

      it 'forwards a cursor verbatim on a follow-up call' do
        request = stub_request(:get, repositories_url)
          .with(query: { cursor: next_cursor })
          .to_return(status: 200, body: repositories_body, headers: json_headers)

        client.repositories(slug: slug, cursor: next_cursor)

        expect(request).to have_been_requested
      end
    end

    context 'when parsing the Link header for cursors (RFC 8288)' do
      def stub_list_with_link(link)
        stub_ar_list(body: repositories_body, headers: json_headers.merge('Link' => link))
      end

      it 'reads the next and prev cursors from the Link header', :aggregate_failures do
        next_url = "#{base_url}/api/v1/#{slug}/repositories?limit=20&cursor=#{next_cursor}"
        prev_url = "#{base_url}/api/v1/#{slug}/repositories?limit=20&cursor=#{prev_cursor}"
        stub_list_with_link(%(<#{next_url}>; rel="next", <#{prev_url}>; rel="prev"))

        page = client.repositories(slug: slug)

        expect(page.next_cursor).to eq(next_cursor)
        expect(page.prev_cursor).to eq(prev_cursor)
      end

      it 'returns a nil prev cursor and logs nothing on the first page (Link carries only rel="next")',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_list_with_link(%(<#{base_url}/api/v1/#{slug}/repositories?cursor=#{next_cursor}>; rel="next"))

        page = client.repositories(slug: slug)

        expect(page.next_cursor).to eq(next_cursor)
        expect(page.prev_cursor).to be_nil
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end

      it 'returns a nil next cursor and logs nothing on the final page (Link carries only rel="prev")',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_list_with_link(%(<#{base_url}/api/v1/#{slug}/repositories?cursor=#{prev_cursor}>; rel="prev"))

        page = client.repositories(slug: slug)

        expect(page.next_cursor).to be_nil
        expect(page.prev_cursor).to eq(prev_cursor)
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end

      it 'returns nil cursors and logs nothing when the response carries no Link header', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_list(body: repositories_body)

        page = client.repositories(slug: slug)

        expect(page.next_cursor).to be_nil
        expect(page.prev_cursor).to be_nil
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end

      it 'returns nil cursors and logs when a link URI is malformed', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_list_with_link('<https://ar/a b?cursor=x>; rel="next"')

        page = client.repositories(slug: slug)

        expect(page.next_cursor).to be_nil
        expect(page.prev_cursor).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(URI::InvalidURIError), hash_including(url: base_url, slug: slug)
        )
      end

      it 'returns a nil next cursor and logs when the next link carries no cursor', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_list_with_link(%(<#{repositories_url}?limit=20>; rel="next"))

        page = client.repositories(slug: slug)

        expect(page.next_cursor).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::Error), hash_including(url: base_url, slug: slug)
        )
      end

      context 'when the parser drops every rel the client reads' do
        shared_examples 'a Link header the parser yields no usable rel from' do
          it 'returns nil cursors and logs the dropped header', :aggregate_failures do
            allow(Gitlab::ErrorTracking).to receive(:log_exception)
            stub_list_with_link(link)

            page = client.repositories(slug: slug)

            expect(page.next_cursor).to be_nil
            expect(page.prev_cursor).to be_nil
            expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
              instance_of(described_class::Error), hash_including(url: base_url, slug: slug)
            )
          end
        end

        context 'when the only rel is the "previous" synonym of "prev"' do
          let(:link) { %(<#{repositories_url}?cursor=#{prev_cursor}>; rel="previous") }

          it_behaves_like 'a Link header the parser yields no usable rel from'
        end

        context 'when the link URI contains a comma, which the parser splits on' do
          let(:link) { %(<#{repositories_url}?cursor=a,b>; rel="next") }

          it_behaves_like 'a Link header the parser yields no usable rel from'
        end

        context 'when the link URI is longer than the parser accepts' do
          let(:link) { %(<#{repositories_url}?cursor=#{'x' * 520}>; rel="next") }

          it_behaves_like 'a Link header the parser yields no usable rel from'
        end
      end
    end

    # A non-Hash body is refused on body_class alone and reports no list_class.
    # The rest share body_class: Hash, so list_class is what tells them apart
    # in Sentry.
    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body',
        status: 204, body: '', body_class: 'NilClass', expect_no_list_class: true
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '{}', body_class: 'Hash', list_class: 'NilClass', label: 'no repositories key'

      # Only the envelope reads. A bare array is refused on the body's own class,
      # before anything looks inside it, so a page of well-formed repository
      # objects is refused exactly as a page of strings is.
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '[{"name":"my-repo"}]', body_class: 'Array', expect_no_list_class: true,
        label: 'bare array of repository objects'
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '["oops"]', body_class: 'Array', expect_no_list_class: true,
        label: 'bare array of strings'

      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '{"repositories":null}', body_class: 'Hash', list_class: 'NilClass',
        label: 'null repositories'
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '{"repositories":{}}', body_class: 'Hash', list_class: 'Hash',
        label: 'object repositories'
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '{"repositories":"oops"}', body_class: 'Hash', list_class: 'String',
        label: 'non-array repositories'
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '{"repositories":["oops"]}', body_class: 'Hash', list_class: 'Array',
        label: 'array of strings'

      # Every element is checked, not just the first. Relaxing the guard to
      # `list.first.is_a?(Hash)` or `list.grep(Hash)` keeps the cases above green
      # while a part-malformed page either drops rows or raises inside
      # Repository.new.
      it_behaves_like 'rejecting an unexpected success body',
        status: 200, body: '{"repositories":[{"name":"my-repo"},"oops"]}', body_class: 'Hash',
        list_class: 'Array', label: 'array mixing objects and strings'
    end

    context 'when attaching the credential through the shared request primitive' do
      it 'attaches the acquired credential as an Authorization: Bearer header' do
        request = stub_request(:get, repositories_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" })
          .to_return(status: 200, body: repositories_body, headers: json_headers)

        client.repositories(slug: slug)

        expect(request).to have_been_requested
      end

      it 'acquires the credential through the token exchange with the current user and slug' do
        stub_ar_list(body: repositories_body)

        client.repositories(slug: slug)

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
      end
    end

    context 'when slug is blank or a bare dot-segment' do
      where(:slug) { [nil, '', '.', '..'] }

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_ar_list(body: repositories_body)

          expect { client.repositories(slug: slug) }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when AR returns 404 (the slug did not resolve to a namespace)' do
      before do
        stub_request(:get, repositories_url)
          .to_return(
            status: 404,
            body: error_envelope(code: 'not_found', message: 'namespace not found', request_id: 'req-404').to_json,
            headers: json_headers
          )
      end

      # AR answers 404 both for a namespace that does not exist and for one the caller may not
      # see, so the absence is reported the way #repository reports it rather than raised.
      it 'returns nil rather than raising' do
        expect(client.repositories(slug: slug)).to be_nil
      end

      it 'logs the envelope, so a slug that drifted from AR is still diagnosable' do
        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError),
            hash_including(url: base_url, slug: slug)) do |error, _context|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-404')
        end

        client.repositories(slug: slug)
      end

      it 'returns nil even when the 404 body is empty' do
        stub_request(:get, repositories_url).to_return(status: 404, body: '')

        expect(client.repositories(slug: slug)).to be_nil
      end
    end

    context 'when the slug contains path separators' do
      let(:slug) { 'grp/x' }

      it 'percent-encodes the slug segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:get, "#{base_url}/api/v1/grp%2Fx/repositories")
          .to_return(status: 200, body: repositories_body, headers: json_headers)
        traversed = stub_request(:get, "#{base_url}/api/v1/grp/x/repositories")

        client.repositories(slug: slug)

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#namespace_statistics' do
    let(:http_method) { :get }
    let(:request_url) { "#{base_url}/api/v1/#{slug}/statistics" }

    let(:statistics_response) do
      {
        'repositories_count' => 7,
        'deduplicated_size_bytes' => 987_654,
        'components_count' => 42,
        'downloads_count' => 0
      }
    end

    def perform
      client.namespace_statistics(slug: slug)
    end

    it 'reads the namespace statistics path with no query and returns the two exposed figures',
      :aggregate_failures do
      request = stub_request(:get, request_url)
        .with(query: {})
        .to_return(status: 200, body: statistics_response.to_json, headers: json_headers)

      result = perform

      expect(request).to have_been_requested
      expect(result).to be_a(ArtifactRegistry::NamespaceStatistics)
      expect(result.repositories_count).to eq(7)
      expect(result.deduplicated_size_bytes).to eq(987_654)
    end

    context 'when handling the credential' do
      let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc') }

      let(:client) do
        described_class.new(base_url: base_url, current_user: current_user,
          token_exchange: token_exchange, service_credential: service_credential)
      end

      it 'sends the per-user token as a Bearer header and no service-token header, never in the URI',
        :aggregate_failures do
        stub_request(:get, request_url)
          .to_return(status: 200, body: statistics_response.to_json, headers: json_headers)

        perform

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:get, request_url).with(headers: { 'Authorization' => "Bearer #{token}" }))
          .to have_been_made
        expect(
          a_request(:get, request_url).with { |req| req.headers.key?(described_class::SERVICE_TOKEN_HEADER) }
        ).not_to have_been_made
        expect(a_request(:get, request_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
        expect(service_credential).not_to have_received(:token)
      end
    end

    context 'when AR answers 404 (the slug did not resolve to a namespace)' do
      it 'returns nil and logs the envelope, so a slug that drifted from AR is still diagnosable',
        :aggregate_failures do
        stub_request(:get, request_url).to_return(
          status: 404,
          body: error_envelope(code: 'not_found', request_id: 'req-404').to_json,
          headers: json_headers
        )

        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError),
            hash_including(url: base_url, slug: slug)) do |error, _context|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-404')
        end

        expect(perform).to be_nil
      end

      it 'logs the request path, so it is distinguishable from the repositories 404 the same slug triggers' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, request_url).to_return(status: 404, body: '', headers: json_headers)

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError),
          hash_including(path: "api/v1/#{slug}/statistics")
        )
      end

      context 'when the 404 body carries no envelope' do
        where(:body) { ['', 'not json'] }

        with_them do
          it 'returns nil' do
            allow(Gitlab::ErrorTracking).to receive(:log_exception)
            stub_request(:get, request_url).to_return(status: 404, body: body, headers: json_headers)

            expect(perform).to be_nil
          end
        end
      end

      it 'reads request_id from the X-Request-Id header when the 404 body carries no envelope',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, request_url)
          .to_return(status: 404, body: '', headers: json_headers.merge('X-Request-Id' => 'req-header-404'))

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError), hash_including(request_id: 'req-header-404')
        )
      end
    end

    context 'when the namespace has never held a repository' do
      it 'reads every figure zero as a figure rather than an absence', :aggregate_failures do
        body = statistics_response.merge('repositories_count' => 0, 'deduplicated_size_bytes' => 0)
        stub_request(:get, request_url).to_return(status: 200, body: body.to_json, headers: json_headers)

        result = perform

        expect(result.repositories_count).to eq(0)
        expect(result.deduplicated_size_bytes).to eq(0)
      end
    end

    context 'when AR answers 200 with a body missing a required key' do
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{}',
        body_class: 'Hash', label: 'neither key'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{"repositories_count":7}',
        body_class: 'Hash', label: 'no deduplicated_size_bytes key'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{"deduplicated_size_bytes":1}',
        body_class: 'Hash', label: 'no repositories_count key'
    end

    context 'when AR answers 200 with a present key whose figure is null' do
      # The guard refuses an absent key, not a null value: a present figure passes to the value
      # object, which decides what a null means, so this must not be tightened to reject null.
      where(:body) do
        [
          '{"repositories_count":null,"deduplicated_size_bytes":5}',
          '{"repositories_count":5,"deduplicated_size_bytes":null}'
        ]
      end

      with_them do
        it 'returns the value object rather than refusing the body', :aggregate_failures do
          stub_request(:get, request_url).to_return(status: 200, body: body, headers: json_headers)

          expect(perform).to be_a(ArtifactRegistry::NamespaceStatistics)
        end
      end
    end

    context 'when AR answers with a mapped error status other than 404' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
        501 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status',
          :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_request(:get, request_url).to_return(
            status: status, body: error_envelope(request_id: 'req-stats-id').to_json, headers: json_headers
          )

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.status).to eq(status)
            expect(error.request_id).to eq('req-stats-id')
          end
        end
      end
    end

    context 'when the body carries only the two figures this client reads' do
      it 'returns the statistics rather than refusing a body without the consumerless keys',
        :aggregate_failures do
        body = { 'repositories_count' => 7, 'deduplicated_size_bytes' => 987_654 }
        stub_request(:get, request_url).to_return(status: 200, body: body.to_json, headers: json_headers)

        result = perform

        expect(result).to be_a(ArtifactRegistry::NamespaceStatistics)
        expect(result.repositories_count).to eq(7)
        expect(result.deduplicated_size_bytes).to eq(987_654)
      end
    end

    context 'when a transport failure occurs on the GET' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'retries once and raises UnavailableError', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, request_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:get, request_url)).to have_been_made.times(retry_options[:max] + 1)
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '["oops"]', body_class: 'Array'
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
    end

    context 'when slug is blank or a bare dot-segment' do
      where(:slug) { [nil, '', '.', '..'] }

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(base_url)}}).to_return(
            status: 200, body: statistics_response.to_json, headers: json_headers
          )

          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug contains path separators' do
      let(:slug) { 'grp/x' }

      it 'percent-encodes the slug segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:get, "#{base_url}/api/v1/grp%2Fx/statistics")
          .to_return(status: 200, body: statistics_response.to_json, headers: json_headers)
        traversed = stub_request(:get, "#{base_url}/api/v1/grp/x/statistics")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#packages' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:request_url) { "#{repository_url}/#{format}/packages" }
    let(:perform) { perform_with }

    let(:maven_package_response) do
      {
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'group_id' => 'com.example.tools',
        'artifact_id' => 'payment-core',
        'last_downloaded_at' => '2026-07-03T09:15:00Z'
      }
    end

    let(:other_maven_package_response) do
      maven_package_response.merge('id' => 'b2c3d4e5-0000-0000-0000-000000000000', 'artifact_id' => 'payment-api')
    end

    let(:list_response) { [maven_package_response, other_maven_package_response] }

    def perform_with(**arguments)
      client.packages(slug: slug, repository_name: name, format: format, **arguments)
    end

    it_behaves_like 'a keyset artifact list read', list_segment: 'packages'

    context 'when the repository format is maven' do
      it 'reads under the maven segment and returns MavenPackage rows on a Page', :aggregate_failures do
        request = stub_ar_list(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page).to be_a(ArtifactRegistry::Page)
        expect(page.nodes).to all(be_a(ArtifactRegistry::MavenPackage))
        expect(page.nodes.map(&:id)).to eq(
          %w[a1b2c3d4-0000-0000-0000-000000000000 b2c3d4e5-0000-0000-0000-000000000000]
        )
        expect(page.nodes.map(&:group_id)).to eq(%w[com.example.tools com.example.tools])
        expect(page.nodes.map(&:artifact_id)).to eq(%w[payment-core payment-api])
      end
    end

    context 'when the repository format is npm' do
      let(:format) { 'npm' }

      let(:npm_package_response) do
        {
          'id' => 'c3d4e5f6-0000-0000-0000-000000000000',
          'name' => '@acme/ui-components',
          'scope' => '@acme',
          'versions_count' => 7,
          'tags_count' => 2,
          'last_downloaded_at' => '2026-07-03T09:15:00Z'
        }
      end

      let(:unscoped_npm_package_response) do
        npm_package_response.merge(
          'id' => 'd4e5f6a7-0000-0000-0000-000000000000',
          'name' => 'ui-components',
          'scope' => nil,
          'versions_count' => 1
        )
      end

      let(:list_response) { [npm_package_response, unscoped_npm_package_response] }

      it 'reads under the npm segment and returns NpmPackage rows carrying name, scope, and the count',
        :aggregate_failures do
        request = stub_ar_list(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page).to be_a(ArtifactRegistry::Page)
        expect(page.nodes).to all(be_a(ArtifactRegistry::NpmPackage))
        expect(page.nodes.map(&:id)).to eq(
          %w[c3d4e5f6-0000-0000-0000-000000000000 d4e5f6a7-0000-0000-0000-000000000000]
        )
        expect(page.nodes.map(&:name)).to eq(['@acme/ui-components', 'ui-components'])
        expect(page.nodes.map(&:scope)).to eq(['@acme', nil])
        expect(page.nodes.map(&:versions_count)).to eq([7, 1])
      end
    end

    context 'when the format is not one the packages endpoint serves' do
      where(:format) { [nil, '', 'docker', 'oci', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end
  end

  describe '#images' do
    let(:format) { 'docker' }
    let(:http_method) { :get }
    let(:request_url) { "#{repository_url}/#{format}/images" }
    let(:perform) { perform_with }

    let(:image_response) do
      {
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'name' => 'api-gateway',
        'last_downloaded_at' => '2026-07-03T09:15:00Z'
      }
    end

    let(:other_image_response) do
      image_response.merge('id' => 'b2c3d4e5-0000-0000-0000-000000000000', 'name' => 'billing-worker')
    end

    let(:list_response) { [image_response, other_image_response] }

    def perform_with(**arguments)
      client.images(slug: slug, repository_name: name, format: format, **arguments)
    end

    it_behaves_like 'a keyset artifact list read', list_segment: 'images'

    context 'when the repository is a container repository' do
      where(:format) { %w[docker oci] }

      with_them do
        it 'reads under the repository format segment and returns Image rows on a Page',
          :aggregate_failures do
          request = stub_ar_list(body: list_response.to_json)

          page = perform

          expect(request).to have_been_requested
          expect(page).to be_a(ArtifactRegistry::Page)
          expect(page.nodes).to all(be_a(ArtifactRegistry::Image))
          expect(page.nodes.map(&:id)).to eq(
            %w[a1b2c3d4-0000-0000-0000-000000000000 b2c3d4e5-0000-0000-0000-000000000000]
          )
          expect(page.nodes.map(&:name)).to eq(%w[api-gateway billing-worker])
        end
      end
    end

    context 'when the format is not one the images endpoint serves' do
      where(:format) { [nil, '', 'maven', 'npm', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end
  end

  describe '#upstream_repositories' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:request_url) { "#{repository_url}/#{format}/upstream_repositories" }
    let(:perform) { perform_with }

    let(:list_response) do
      [
        association_response(id: 'a1b2c3d4-0000-0000-0000-000000000000', position: 1,
          upstream_id: 'b1000000-0000-0000-0000-000000000000', upstream_name: 'payment-core', kind: 'hosted'),
        association_response(id: 'a2b3c4d5-0000-0000-0000-000000000000', position: 2,
          upstream_id: 'b2000000-0000-0000-0000-000000000000', upstream_name: 'payment-mirror', kind: 'remote')
      ]
    end

    def association_response(id:, position:, upstream_id:, upstream_name:, kind:)
      {
        'id' => id,
        'position' => position,
        'upstream_repository' => { 'id' => upstream_id, 'name' => upstream_name, 'format' => format, 'kind' => kind }
      }
    end

    def perform_with(**arguments)
      client.upstream_repositories(slug: slug, repository_name: name, format: format, **arguments)
    end

    context 'with a populated upstream list' do
      where(:format) { %w[maven npm docker oci] }

      with_them do
        it 'reads under the format upstream_repositories segment and returns association value objects',
          :aggregate_failures do
          request = stub_ar_list(body: list_response.to_json)

          result = perform

          expect(request).to have_been_requested
          expect(result).to be_an(Array)
          expect(result).to all(be_a(ArtifactRegistry::UpstreamRepositoryAssociation))
          expect(result.map(&:id)).to eq(
            %w[a1b2c3d4-0000-0000-0000-000000000000 a2b3c4d5-0000-0000-0000-000000000000]
          )
          expect(result.map(&:position)).to eq([1, 2])
          expect(result.map { |a| a.upstream_repository.name }).to eq(%w[payment-core payment-mirror])
          expect(result.map { |a| a.upstream_repository.kind }).to eq(%w[hosted remote])
          expect(result.map { |a| a.upstream_repository.format }).to all(eq(format))
        end
      end
    end

    it 'returns every element in AR order and hands back a bare array with no cursors', :aggregate_failures do
      ordered = Array.new(20) do |index|
        position = index + 1
        suffix = position.to_s.rjust(2, '0')
        association_response(id: "a#{suffix}00000-0000-0000-0000-000000000000", position: position,
          upstream_id: "b#{suffix}00000-0000-0000-0000-000000000000",
          upstream_name: "upstream-#{position}", kind: 'hosted')
      end
      stub_ar_list(body: ordered.to_json)

      result = perform

      expect(result.size).to eq(20)
      expect(result).not_to respond_to(:next_cursor)
      expect(result.map(&:position)).to eq((1..20).to_a)
    end

    it 'returns an empty array for a virtual repository with no upstreams' do
      stub_ar_list(body: [].to_json)

      expect(perform).to eq([])
    end

    context 'when AR returns 404' do
      it 'returns nil rather than raising, covering a missing, non-virtual, or unseen repository' do
        stub_request(:get, request_url)
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect(perform).to be_nil
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status', :aggregate_failures do
          stub_request(:get, request_url).to_return(
            status: status, body: error_envelope(request_id: 'req-upstream-id').to_json, headers: json_headers
          )

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.request_id).to eq('req-upstream-id')
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{}', body_class: 'Hash'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '["oops"]', body_class: 'Array'
    end

    it 'attaches the credential as a Bearer header, never in the request URI', :aggregate_failures do
      request = stub_request(:get, request_url)
        .with(headers: { 'Authorization' => "Bearer #{token}" })
        .to_return(status: 200, body: list_response.to_json, headers: json_headers)

      perform

      expect(request).to have_been_requested
      expect(a_request(:get, request_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
    end

    context 'when the format is not one the client lists' do
      where(:format) { [nil, '', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when slug or the repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        nil        | 'my-repo'
        ''         | 'my-repo'
        '.'        | 'my-repo'
        '..'       | 'my-repo'
        'my-group' | nil
        'my-group' | ''
        'my-group' | '.'
        'my-group' | '..'
      end

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when the slug and repository name contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/upstream_repositories"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/upstream_repositories")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  shared_examples 'a single-artifact read' do |collection:|
    context 'when AR returns 404' do
      it 'returns nil rather than raising, and reports nothing to error tracking', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, request_url)
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect(perform).to be_nil
        # Deliberately silent, unlike the list reads, so a crawled bad URL is not a Sentry event.
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end

      it 'returns nil even when the 404 body is empty' do
        stub_request(:get, request_url).to_return(status: 404, body: '')

        expect(perform).to be_nil
      end

      it 'returns nil even when a 404 body is unparseable but labelled JSON, as an intermediary sends' do
        stub_request(:get, request_url).to_return(status: 404, body: 'not json', headers: json_headers)

        expect(perform).to be_nil
      end
    end

    context 'with no keyset query parameters' do
      it 'issues the read on the artifact detail path with no query string' do
        stub_request(:get, request_url).to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

        perform

        expect(a_request(:get, request_url).with { |req| req.uri.query.blank? }).to have_been_made
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status', :aggregate_failures do
          stub_request(:get, request_url).to_return(
            status: status,
            body: error_envelope(request_id: 'req-detail-id').to_json,
            headers: json_headers
          )

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.request_id).to eq('req-detail-id')
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when a transport failure occurs on the GET' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'retries the idempotent GET once and then raises UnavailableError', :aggregate_failures do
        stub_request(:get, request_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:get, request_url)).to have_been_made.times(retry_options[:max] + 1)
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      # A 200 {} passes the Hash check but has no id, so it must fail loud rather than resolve present.
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{}', body_class: 'Hash'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '["oops"]', body_class: 'Array'
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
    end

    context 'when handling the credential' do
      it 'acquires it for the slug and attaches it as a Bearer header, never in the request URI',
        :aggregate_failures do
        request = stub_request(:get, request_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" })
          .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

        perform

        expect(request).to have_been_requested
        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:get, request_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end

      it 'redacts a credential AR echoes in an error envelope, in both the raised and the logged error',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        echoed = "rejected: Authorization: Bearer #{jwt_credential}"
        stub_request(:get, request_url)
          .to_return(status: 503, body: error_envelope(message: echoed).to_json, headers: json_headers)

        expect { perform }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).not_to include(jwt_credential)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
          expect(logged.message).not_to include(jwt_credential)
        end
      end
    end

    context 'when slug or the repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        nil        | 'my-repo'
        ''         | 'my-repo'
        '.'        | 'my-repo'
        '..'       | 'my-repo'
        'my-group' | nil
        'my-group' | ''
        'my-group' | '.'
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(repository_url)}}).to_return(
            status: 200, body: artifact_response.to_json, headers: json_headers
          )

          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    # A malformed id resolves to the same not-found outcome as a real 404 rather than raising the
    # way a blank slug or repository name does, so a bad deep link exposes no id-syntax oracle.
    # A non-String id whose to_s is a dot segment is caught too, so it cannot reach the wire.
    context 'when the id is blank or a bare dot-segment' do
      where(:artifact_id) { [nil, '', '.', '..', :'.', :'..'] }

      with_them do
        it 'resolves nil without contacting AR, indistinguishable from a real 404', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(repository_url)}}).to_return(
            status: 200, body: artifact_response.to_json, headers: json_headers
          )

          expect(perform).to be_nil
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug, repository name, and id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:artifact_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{collection}/a%2Fb"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)
        traversed = stub_request(:get, "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{collection}/a/b")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#package' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:artifact_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/packages/#{artifact_id}" }

    let(:artifact_response) do
      {
        'id' => artifact_id,
        'group_id' => 'com.example.tools',
        'artifact_id' => 'payment-core'
      }
    end

    def perform
      client.package(slug: slug, repository_name: name, format: format, id: artifact_id)
    end

    it_behaves_like 'a single-artifact read', collection: 'packages'

    context 'when the repository format is maven' do
      it 'reads under the maven packages segment and returns a MavenPackage', :aggregate_failures do
        request = stub_request(:get, request_url)
          .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

        result = perform

        expect(request).to have_been_requested
        expect(result).to be_a(ArtifactRegistry::MavenPackage)
        expect(result.id).to eq(artifact_id)
        expect(result.group_id).to eq('com.example.tools')
        expect(result.artifact_id).to eq('payment-core')
      end
    end

    context 'when the repository format is npm' do
      let(:format) { 'npm' }

      let(:artifact_response) do
        {
          'id' => artifact_id,
          'name' => '@acme/ui-components',
          'scope' => '@acme',
          'versions_count' => 7
        }
      end

      it 'reads under the npm packages segment and returns an NpmPackage', :aggregate_failures do
        request = stub_request(:get, request_url)
          .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

        result = perform

        expect(request).to have_been_requested
        expect(result).to be_a(ArtifactRegistry::NpmPackage)
        expect(result.id).to eq(artifact_id)
        expect(result.name).to eq('@acme/ui-components')
        expect(result.scope).to eq('@acme')
        expect(result.versions_count).to eq(7)
      end
    end

    context 'when the format is not one the packages endpoint serves' do
      let(:list_response) { [artifact_response] }

      where(:format) { [nil, '', 'docker', 'oci', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    # The second line of defense behind guard_format!: a format added to PACKAGE_FORMATS without
    # a value-object class here must fail loud rather than resolving to whichever branch is last.
    context 'when a package format is allowed but has no value-object class' do
      before do
        stub_const("#{described_class}::PACKAGE_FORMATS", %w[maven npm conda])
      end

      let(:format) { 'conda' }

      it 'raises ArgumentError from package_class rather than reading a wrong class' do
        expect { perform }.to raise_error(ArgumentError, /format must be one of/)
      end
    end
  end

  describe '#image' do
    let(:format) { 'docker' }
    let(:http_method) { :get }
    let(:artifact_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/images/#{artifact_id}" }

    let(:artifact_response) do
      {
        'id' => artifact_id,
        'name' => 'api-gateway'
      }
    end

    def perform
      client.image(slug: slug, repository_name: name, format: format, id: artifact_id)
    end

    it_behaves_like 'a single-artifact read', collection: 'images'

    context 'when the repository is a container repository' do
      where(:format) { %w[docker oci] }

      with_them do
        it 'reads under the repository format images segment and returns an Image', :aggregate_failures do
          request = stub_request(:get, request_url)
            .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

          result = perform

          expect(request).to have_been_requested
          expect(result).to be_a(ArtifactRegistry::Image)
          expect(result.id).to eq(artifact_id)
          expect(result.name).to eq('api-gateway')
        end
      end
    end

    context 'when the format is not one the images endpoint serves' do
      let(:list_response) { [artifact_response] }

      where(:format) { [nil, '', 'maven', 'npm', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end
  end

  describe '#versions' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:package_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/packages/#{package_id}/versions" }
    let(:perform) { perform_with }

    let(:version_response) do
      {
        'id' => 'v1000-0000-0000-0000-000000000000',
        'version' => '1.10.0',
        'created_at' => '2026-07-03T09:15:00Z',
        'created_by' => '101',
        'project_id' => '202',
        'git_commit_sha' => 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
      }
    end

    let(:other_version_response) do
      version_response.merge('id' => 'v0900-0000-0000-0000-000000000000', 'version' => '1.9.0')
    end

    let(:list_response) { [version_response, other_version_response] }

    def perform_with(**arguments)
      client.versions(slug: slug, repository_name: name, format: format, package_id: package_id, **arguments)
    end

    it_behaves_like 'a keyset artifact list read', list_segment: 'packages', nested: true

    context 'when the repository format is maven' do
      it 'reads the versions sub-collection and returns Version rows on a Page', :aggregate_failures do
        request = stub_ar_list(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page).to be_a(ArtifactRegistry::Page)
        expect(page.nodes).to all(be_a(ArtifactRegistry::Version))
        expect(page.nodes.map(&:version)).to eq(%w[1.10.0 1.9.0])
      end

      it 'passes the three attribution references through unresolved, as raw opaque strings',
        :aggregate_failures do
        stub_ar_list(body: [version_response].to_json)

        version = perform.nodes.first

        expect(version.created_by).to eq('101')
        expect(version.project_id).to eq('202')
        expect(version.git_commit_sha).to eq('deadbeefdeadbeefdeadbeefdeadbeefdeadbeef')
      end

      it 'logs the failing package id on a 404, so per-package drift stays diagnosable' do
        stub_request(:get, request_url).to_return(
          status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers
        )

        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError), hash_including(slug: slug, id: package_id))

        expect(perform).to be_nil
      end

      # A continuation read whose package was deleted between pages 404s and resolves nil, the same
      # not-found outcome as a first-page read. The connection consumer (Step 6) guards the nil.
      it 'resolves nil when a cursor-supplied continuation read 404s' do
        stub_request(:get, request_url)
          .with(query: hash_including(cursor: 'next-cursor'))
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect(perform_with(cursor: 'next-cursor')).to be_nil
      end
    end

    context 'when the repository format is npm' do
      let(:format) { 'npm' }

      it 'reads under the npm packages segment' do
        request = stub_ar_list(body: list_response.to_json)

        perform

        expect(request).to have_been_requested
      end
    end

    context 'with the sort and order query parameters' do
      it 'forwards sort and order alongside the keyset parameters' do
        request = stub_request(:get, request_url)
          .with(query: { sort: 'version', order: 'asc', limit: '100', cursor: 'opaque-cursor' })
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)

        perform_with(sort: 'version', order: 'asc', limit: 100, cursor: 'opaque-cursor')

        expect(request).to have_been_requested
      end

      it 'omits sort and order when the caller supplies neither, leaving the read on the contract sort' do
        stub_ar_list(body: list_response.to_json)

        perform

        expect(a_request(:get, request_url).with { |req| req.uri.query.blank? }).to have_been_made
      end
    end

    context 'when the package id is blank or a bare dot-segment' do
      where(:package_id) { [nil, '', '.', '..'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when the format is not one the packages endpoint serves' do
      where(:format) { [nil, '', 'docker', 'oci', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    # The shared path-separator case binds a single-segment path; the versions read nests the
    # package id and the versions segment, so it is asserted here.
    context 'when the slug, repository name, and package id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:package_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/packages/a%2Fb/versions"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/packages/a/b/versions")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#version' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:artifact_id) { 'v1000-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/versions/#{artifact_id}" }

    let(:artifact_response) do
      {
        'id' => artifact_id,
        'version' => '1.10.0',
        'created_at' => '2026-07-03T09:15:00Z',
        'size' => 987_654,
        'package_id' => 'pkg-0000-0000-0000-000000000000',
        'created_by' => '101',
        'project_id' => '202',
        'git_commit_sha' => 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
      }
    end

    def perform
      client.version(slug: slug, repository_name: name, format: format, version_id: artifact_id)
    end

    it_behaves_like 'a single-artifact read', collection: 'versions'

    context 'when the repository format is maven' do
      it 'reads the version detail path and returns a Version carrying the new readers',
        :aggregate_failures do
        request = stub_request(:get, request_url)
          .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

        result = perform

        expect(request).to have_been_requested
        expect(result).to be_a(ArtifactRegistry::Version)
        expect(result.id).to eq(artifact_id)
        expect(result.version).to eq('1.10.0')
        expect(result.size).to eq(987_654)
        expect(result.package_id).to eq('pkg-0000-0000-0000-000000000000')
      end

      # size is required in the contract, so a version AR has never sized sends explicit JSON null;
      # package_id and npm_metadata are unconfirmed keys AR does not serialize yet, so they are
      # genuinely absent. Both read nil, and the two cases are shaped as the contract sends them.
      it 'reads a null size and the absent package_id and npm metadata as nil', :aggregate_failures do
        stub_request(:get, request_url).to_return(
          status: 200,
          body: {
            'id' => artifact_id, 'version' => '1.10.0', 'created_at' => '2026-07-03T09:15:00Z',
            'size' => nil, 'last_downloaded_at' => nil, 'created_by' => nil, 'project_id' => nil,
            'git_commit_sha' => nil
          }.to_json,
          headers: json_headers
        )

        result = perform

        expect(result.size).to be_nil
        expect(result.package_id).to be_nil
        expect(result.npm_metadata).to be_nil
      end
    end

    context 'when the repository format is npm' do
      let(:format) { 'npm' }

      let(:artifact_response) do
        {
          'id' => artifact_id,
          'version' => '1.10.0',
          'npm_metadata' => { 'description' => 'A design system' }
        }
      end

      it 'reads under the npm versions segment and passes the parsed metadata Hash through',
        :aggregate_failures do
        request = stub_request(:get, request_url)
          .to_return(status: 200, body: artifact_response.to_json, headers: json_headers)

        result = perform

        expect(request).to have_been_requested
        expect(result).to be_a(ArtifactRegistry::Version)
        expect(result.npm_metadata).to eq({ 'description' => 'A design system' })
      end
    end

    context 'when the format is not one the versions endpoint serves' do
      let(:list_response) { [artifact_response] }

      where(:format) { [nil, '', 'docker', 'oci', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end
  end

  describe '#version_statistics' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:version_id) { 'v1000-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/versions/#{version_id}/statistics" }

    let(:statistics_response) { { 'files_count' => 12 } }

    def perform
      client.version_statistics(slug: slug, repository_name: name, format: format, version_id: version_id)
    end

    context 'when the route is served (Phase 8)' do
      it 'reads the statistics path and returns a VersionStatistics carrying files_count',
        :aggregate_failures do
        request = stub_request(:get, request_url)
          .to_return(status: 200, body: statistics_response.to_json, headers: json_headers)

        result = perform

        expect(request).to have_been_requested
        expect(result).to be_a(ArtifactRegistry::VersionStatistics)
        expect(result.files_count).to eq(12)
      end
    end

    context 'when AR answers 404, the outcome while the route is unregistered' do
      # Every 404 shape resolves nil: enveloped, empty-body, and the unparseable-but-JSON body an
      # intermediary sends. AR's middleware rewrites the mux 404 into the envelope, but the client
      # tolerates all three so a middleware change cannot break the read.
      where(:body) do
        [
          '{"error":{"code":"not_found"}}',
          '',
          'not json'
        ]
      end

      with_them do
        it 'returns nil and reports nothing to error tracking, so an unserved count is not a Sentry event',
          :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_request(:get, request_url).to_return(status: 404, body: body, headers: json_headers)

          expect(perform).to be_nil
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR answers 501, the outcome once the route is registered ahead of its handler' do
      it 'returns nil rather than raising, though it still emits one terminal error-tracking event',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, request_url)
          .to_return(status: 501, body: error_envelope(code: 'not_implemented').to_json, headers: json_headers)

        expect(perform).to be_nil
        # The field renders an absent count (no raise), but the shared terminal path reports the 501
        # before the rescue swallows it. Diverting that event is the documented follow-up.
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).once
      end
    end

    context 'when AR answers with a mapped error status other than 404 or 501' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status',
          :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_request(:get, request_url).to_return(
            status: status, body: error_envelope(request_id: 'req-stats-id').to_json, headers: json_headers
          )

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.status).to eq(status)
            expect(error.request_id).to eq('req-stats-id')
          end
        end
      end
    end

    context 'when a transport failure occurs on the GET' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'retries once and raises UnavailableError rather than resolving nil through the 501 carve-out',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, request_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:get, request_url)).to have_been_made.times(retry_options[:max] + 1)
      end
    end

    context 'when handling the credential' do
      it 'acquires it for the slug and attaches it as a Bearer header, never in the request URI',
        :aggregate_failures do
        request = stub_request(:get, request_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" })
          .to_return(status: 200, body: statistics_response.to_json, headers: json_headers)

        perform

        expect(request).to have_been_requested
        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:get, request_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end

    context 'when AR answers 200 with a body carrying no files_count' do
      # Unlike a single-artifact read, a hollow body is not a serialization fault here: files_count
      # is a nullable rendered value (S06 criterion 12), so a present object with a nil count is the
      # contract, not a raise. Pinned so a later reviewer does not "correct" it to raise_unexpected.
      it 'returns a present VersionStatistics whose count reads nil', :aggregate_failures do
        stub_request(:get, request_url).to_return(status: 200, body: '{}', headers: json_headers)

        expect(perform).to be_a(ArtifactRegistry::VersionStatistics)
        expect(perform.files_count).to be_nil
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '["oops"]', body_class: 'Array'
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
    end

    context 'when slug, repository name, or version id is blank or a bare dot-segment' do
      where(:slug, :name, :version_id) do
        nil        | 'my-repo' | 'v1'
        ''         | 'my-repo' | 'v1'
        '.'        | 'my-repo' | 'v1'
        '..'       | 'my-repo' | 'v1'
        'my-group' | nil       | 'v1'
        'my-group' | ''        | 'v1'
        'my-group' | '..'      | 'v1'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | ''
        'my-group' | 'my-repo' | '.'
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(base_url)}}).to_return(
            status: 200, body: statistics_response.to_json, headers: json_headers
          )

          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the format is not one the versions endpoint serves' do
      where(:format) { [nil, '', 'docker', 'oci', 'not-a-format'] }

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(repository_url)}}).to_return(
            status: 200, body: statistics_response.to_json, headers: json_headers
          )

          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug, repository name, and version id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:version_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/versions/a%2Fb/statistics"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: statistics_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/versions/a/b/statistics")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  # The 501 carve-out is scoped to #version_statistics: any other read maps 501 to UnavailableError
  # like a 5xx. Asserted on #version to prove the carve-out did not widen the shared mapping.
  describe 'the 501 mapping outside #version_statistics' do
    it 'keeps UnavailableError on #version, so the statistics carve-out is not global' do
      url = "#{repository_url}/maven/versions/v1000-0000-0000-0000-000000000000"
      stub_request(:get, url)
        .to_return(status: 501, body: error_envelope(code: 'not_implemented').to_json, headers: json_headers)

      expect do
        client.version(slug: slug, repository_name: name, format: 'maven',
          version_id: 'v1000-0000-0000-0000-000000000000')
      end.to raise_error(described_class::UnavailableError)
    end
  end

  describe '#version_files' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:version_id) { 'v1000-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/versions/#{version_id}/files" }
    let(:perform) { perform_with }

    let(:maven_file_response) do
      {
        'id' => 'f1000-0000-0000-0000-000000000000',
        'file_name' => 'payment-core-1.10.0.jar',
        'size' => 987_654,
        'sha256' => 'a' * 64,
        'sha1' => 'b' * 40,
        'sha512' => 'c' * 128,
        'md5' => 'd' * 32
      }
    end

    let(:other_maven_file_response) do
      maven_file_response.merge('id' => 'f0900-0000-0000-0000-000000000000', 'file_name' => 'payment-core-1.10.0.pom')
    end

    let(:list_response) { [maven_file_response, other_maven_file_response] }

    def perform_with(**arguments)
      client.version_files(slug: slug, repository_name: name, format: format, version_id: version_id, **arguments)
    end

    it_behaves_like 'a keyset artifact list read', list_segment: 'versions', nested: true

    context 'when the repository format is maven' do
      it 'reads the files sub-collection and returns MavenFile rows on a Page', :aggregate_failures do
        request = stub_ar_list(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page).to be_a(ArtifactRegistry::Page)
        expect(page.nodes).to all(be_a(ArtifactRegistry::MavenFile))
        expect(page.nodes.map(&:file_name)).to eq(%w[payment-core-1.10.0.jar payment-core-1.10.0.pom])
      end

      it 'carries the Maven checksum set and a null md5 or omitted created_at read as nil',
        :aggregate_failures do
        stub_ar_list(body: [maven_file_response.merge('md5' => nil)].to_json)

        file = perform.nodes.first

        expect(file.sha1).to eq('b' * 40)
        expect(file.sha512).to eq('c' * 128)
        expect(file.md5).to be_nil
        expect(file.created_at).to be_nil
      end

      it 'logs the failing version id on a 404, so per-version drift stays diagnosable' do
        stub_request(:get, request_url).to_return(
          status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers
        )

        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError), hash_including(slug: slug, id: version_id))

        expect(perform).to be_nil
      end

      # A continuation read whose version was deleted between pages 404s and resolves nil, the same
      # not-found outcome as a first-page read. The connection consumer (Step 6) guards the nil.
      it 'resolves nil when a cursor-supplied continuation read 404s' do
        stub_request(:get, request_url)
          .with(query: hash_including(cursor: 'next-cursor'))
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect(perform_with(cursor: 'next-cursor')).to be_nil
      end
    end

    context 'when the repository format is npm' do
      let(:format) { 'npm' }

      let(:npm_file_response) do
        {
          'id' => 'f1000-0000-0000-0000-000000000000',
          'file_name' => 'ui-components-1.10.0.tgz',
          'size' => 54_321,
          'sha256' => 'a' * 64,
          'created_at' => '2026-07-03T09:15:00Z'
        }
      end

      let(:list_response) { [npm_file_response] }

      it 'reads under the npm versions segment and returns NpmFile rows', :aggregate_failures do
        request = stub_ar_list(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page.nodes).to all(be_a(ArtifactRegistry::NpmFile))
        expect(page.nodes.first.created_at).to eq(DateTime.iso8601('2026-07-03T09:15:00Z'))
      end

      it 'reads a null npm created_at as nil rather than raising' do
        stub_ar_list(body: [npm_file_response.merge('created_at' => nil)].to_json)

        expect(perform.nodes.first.created_at).to be_nil
      end
    end

    context 'when the version id is blank or a bare dot-segment' do
      where(:version_id) { [nil, '', '.', '..'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when the format is not one the versions endpoint serves' do
      where(:format) { [nil, '', 'docker', 'oci', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    # The second line of defense behind guard_format!: a format added to PACKAGE_FORMATS without a
    # value-object class here must fail loud rather than resolving to whichever branch is last.
    context 'when a package format is allowed but has no file value-object class' do
      before do
        stub_const("#{described_class}::PACKAGE_FORMATS", %w[maven npm conda])
      end

      let(:format) { 'conda' }

      it 'raises ArgumentError from file_class rather than reading a wrong class' do
        expect { perform }.to raise_error(ArgumentError, /format must be one of/)
      end
    end

    # The shared example skips its path-separator case under nested: true, so the encoding of a
    # nested read (the version id plus the files segment) is asserted here rather than there.
    context 'when the slug, repository name, and version id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:version_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/versions/a%2Fb/files"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/versions/a/b/files")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#npm_dist_tags' do
    # The format segment is a literal in the method, not a caller argument; this names the single
    # place the spec states it, and the encoding test below reuses it.
    let(:format) { 'npm' }
    let(:http_method) { :get }
    let(:package_id) { 'p1000-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/packages/#{package_id}/tags" }
    let(:perform) { perform_with }

    let(:dist_tag_response) do
      {
        'id' => 't1000-0000-0000-0000-000000000000',
        'name' => 'latest',
        'version_id' => 'v1000-0000-0000-0000-000000000000',
        'version' => '1.10.0'
      }
    end

    let(:other_dist_tag_response) do
      dist_tag_response.merge('id' => 't0900-0000-0000-0000-000000000000', 'name' => 'beta', 'version' => '1.11.0-beta')
    end

    let(:list_response) { [dist_tag_response, other_dist_tag_response] }

    def perform_with(**arguments)
      client.npm_dist_tags(slug: slug, repository_name: name, package_id: package_id, **arguments)
    end

    it_behaves_like 'a keyset artifact list read', list_segment: 'packages', nested: true

    it 'reads the dist-tag sub-collection under the literal npm segment and returns NpmDistTag rows',
      :aggregate_failures do
      request = stub_ar_list(body: list_response.to_json)

      page = perform

      expect(request).to have_been_requested
      expect(page).to be_a(ArtifactRegistry::Page)
      expect(page.nodes).to all(be_a(ArtifactRegistry::NpmDistTag))
      expect(page.nodes.map(&:name)).to eq(%w[latest beta])
      expect(page.nodes.first.version_id).to eq('v1000-0000-0000-0000-000000000000')
      expect(page.nodes.first.version).to eq('1.10.0')
    end

    it 'logs the failing package id on a 404, so per-package drift stays diagnosable' do
      stub_request(:get, request_url).to_return(
        status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers
      )

      expect(Gitlab::ErrorTracking).to receive(:log_exception)
        .with(an_instance_of(described_class::ApiError), hash_including(slug: slug, id: package_id))

      expect(perform).to be_nil
    end

    context 'when the package id is blank or a bare dot-segment' do
      where(:package_id) { [nil, '', '.', '..'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    # The shared path-separator case is skipped under nested: true, so the encoding of the nested
    # package id and the tags segment is asserted here.
    context 'when the slug, repository name, and package id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:package_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/packages/a%2Fb/tags"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/packages/a/b/tags")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#manifests' do
    let(:format) { 'docker' }
    let(:http_method) { :get }
    let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:request_url) { "#{repository_url}/#{format}/images/#{image_id}/manifests" }
    let(:default_query) { { include_referrers: 'false' } }

    let(:manifest_response) do
      {
        'id' => 'm1000-0000-0000-0000-000000000000',
        'digest' => 'sha256:aaaa',
        'media_type' => 'application/vnd.oci.image.manifest.v1+json',
        'artifact_type' => nil,
        'subject_digest' => nil,
        'size' => 2048,
        'created_at' => '2026-07-03T09:15:00Z',
        'architecture' => 'amd64',
        'os' => 'linux',
        'os_variant' => nil,
        'tags_count' => 2,
        'referrers_count' => 0,
        'children_count' => 0,
        'tags_preview' => %w[latest v1],
        'parents_preview' => ['sha256:parent'],
        'children_preview' => [
          { 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }
        ]
      }
    end

    let(:other_manifest_response) do
      manifest_response.merge('id' => 'm0900-0000-0000-0000-000000000000', 'digest' => 'sha256:bbbb')
    end

    let(:list_response) { [manifest_response, other_manifest_response] }

    def perform_with(**arguments)
      client.manifests(slug: slug, repository_name: name, format: format, image_id: image_id, **arguments)
    end

    def perform
      perform_with
    end

    # #manifests always sends include_referrers, so the shared keyset example (which asserts a
    # queryless request) does not fit; the equivalent coverage is inlined here.
    def stub_manifests(body:, status: 200, headers: json_headers, query: default_query)
      stub_request(:get, request_url).with(query: query).to_return(status: status, body: body, headers: headers)
    end

    context 'when AR returns a page of manifests' do
      it 'reads the manifests sub-collection and returns Manifest rows on a Page', :aggregate_failures do
        request = stub_manifests(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page).to be_a(ArtifactRegistry::Page)
        expect(page.nodes).to all(be_a(ArtifactRegistry::Manifest))
        expect(page.nodes.map(&:digest)).to eq(%w[sha256:aaaa sha256:bbbb])
      end

      it 'exposes the nullable referrer fields without inspecting them', :aggregate_failures do
        stub_manifests(body: [manifest_response].to_json)

        manifest = perform.nodes.first

        expect(manifest.artifact_type).to be_nil
        expect(manifest.subject_digest).to be_nil
        expect(manifest.size).to eq(2048)
      end

      it 'exposes the platform triple and counts the list row carries', :aggregate_failures do
        stub_manifests(body: [manifest_response].to_json)

        manifest = perform.nodes.first

        expect(manifest.architecture).to eq('amd64')
        expect(manifest.os).to eq('linux')
        expect(manifest.os_variant).to be_nil
        expect(manifest.tags_count).to eq(2)
        expect(manifest.referrers_count).to eq(0)
        expect(manifest.children_count).to eq(0)
      end

      it 'exposes the preview arrays the list row carries', :aggregate_failures do
        stub_manifests(body: [manifest_response].to_json)

        manifest = perform.nodes.first

        expect(manifest.tags_preview).to eq(%w[latest v1])
        expect(manifest.parents_preview).to eq(['sha256:parent'])
        expect(manifest.children_preview).to eq(
          [{ 'digest' => 'sha256:child', 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }]
        )
      end

      it 'drops malformed preview entries and reads an absent preview as nil', :aggregate_failures do
        body = [manifest_response.merge(
          'tags_preview' => ['latest', 123],
          'children_preview' => [{ 'digest' => 'sha256:child' }, 'oops'],
          'parents_preview' => nil
        )]
        stub_manifests(body: body.to_json)

        manifest = perform.nodes.first

        expect(manifest.tags_preview).to eq(['latest'])
        expect(manifest.children_preview).to eq([{ 'digest' => 'sha256:child' }])
        expect(manifest.parents_preview).to be_nil
      end

      it 'returns an empty page for an image that holds no manifests' do
        stub_manifests(body: [].to_json)

        expect(perform.nodes).to eq([])
      end
    end

    context 'when the repository is an oci repository' do
      let(:format) { 'oci' }

      it 'reads under the oci images segment' do
        request = stub_manifests(body: list_response.to_json)

        perform

        expect(request).to have_been_requested
      end
    end

    context 'with the include_referrers argument' do
      it 'sends include_referrers=false when the caller omits it, matching the endpoint default' do
        request = stub_manifests(body: list_response.to_json, query: { include_referrers: 'false' })

        perform

        expect(request).to have_been_requested
      end

      it 'forwards include_referrers=true when the caller passes true' do
        request = stub_manifests(body: list_response.to_json, query: { include_referrers: 'true' })

        perform_with(include_referrers: true)

        expect(request).to have_been_requested
      end

      it 'reads a "false" string as false rather than flipping referrers on' do
        request = stub_manifests(body: list_response.to_json, query: { include_referrers: 'false' })

        perform_with(include_referrers: 'false')

        expect(request).to have_been_requested
      end
    end

    context 'with the sort and order query parameters' do
      it 'forwards sort and order alongside include_referrers and the keyset parameters' do
        request = stub_manifests(
          body: list_response.to_json,
          query: { sort: 'created_at', order: 'asc', limit: '100', cursor: 'opaque-cursor',
                   include_referrers: 'false' }
        )

        perform_with(sort: 'created_at', order: 'asc', limit: 100, cursor: 'opaque-cursor')

        expect(request).to have_been_requested
      end
    end

    context 'when parsing the Link header for cursors' do
      it 'reads the next and prev cursors from the Link header', :aggregate_failures do
        next_url = "#{request_url}?cursor=#{next_cursor}"
        prev_url = "#{request_url}?cursor=#{prev_cursor}"
        stub_manifests(
          body: list_response.to_json,
          headers: json_headers.merge('Link' => %(<#{next_url}>; rel="next", <#{prev_url}>; rel="prev"))
        )

        page = perform

        expect(page.next_cursor).to eq(next_cursor)
        expect(page.prev_cursor).to eq(prev_cursor)
      end
    end

    context 'when AR returns 404' do
      it 'returns nil rather than raising' do
        stub_manifests(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(perform).to be_nil
      end

      it 'logs the failing image id, so per-image drift stays diagnosable' do
        stub_manifests(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError), hash_including(slug: slug, id: image_id))

        expect(perform).to be_nil
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status', :aggregate_failures do
          stub_manifests(status: status, body: error_envelope(request_id: 'req-manifests-id').to_json)

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.request_id).to eq('req-manifests-id')
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError for a 200 that is not an array', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_manifests(body: '{}')

        expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the image id is blank or a bare dot-segment' do
      where(:image_id) { [nil, '', '.', '..'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when the format is not one the images endpoint serves' do
      where(:format) { [nil, '', 'maven', 'npm', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when the slug, repository name, and image id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:image_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/images/a%2Fb/manifests"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .with(query: default_query)
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/images/a/b/manifests")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#manifest' do
    let(:format) { 'docker' }
    let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:digest) { "sha256:#{'1' * 64}" }
    let(:request_url) do
      "#{repository_url}/#{format}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}"
    end

    # The detail resource: every list field plus the four arrays that replace the list previews.
    let(:manifest_response) do
      {
        'id' => 'm1000-0000-0000-0000-000000000000',
        'digest' => digest,
        'media_type' => 'application/vnd.oci.image.index.v1+json',
        'artifact_type' => nil,
        'subject_digest' => nil,
        'size' => 4096,
        'created_at' => '2026-07-03T09:15:00Z',
        'architecture' => nil,
        'os' => nil,
        'os_variant' => nil,
        'tags' => %w[latest 1.2.3],
        'tags_count' => 2,
        'children' => [
          { 'digest' => "sha256:#{'a' * 64}", 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }
        ],
        'children_count' => 1,
        'parent_digests' => [],
        'parents_count' => 0,
        'referrers_count' => 0,
        'annotations' => { 'org.opencontainers.image.title' => 'demo' }
      }
    end

    def perform
      client.manifest(slug: slug, repository_name: name, format: format, image_id: image_id, digest: digest)
    end

    def stub_manifest(body:, status: 200, headers: json_headers)
      stub_request(:get, request_url).to_return(status: status, body: body, headers: headers)
    end

    context 'when AR returns the manifest detail' do
      it 'reads it by digest and returns a ManifestDetail carrying the arrays', :aggregate_failures do
        request = stub_manifest(body: manifest_response.to_json)

        detail = perform

        expect(request).to have_been_requested
        expect(detail).to be_a(ArtifactRegistry::ManifestDetail)
        expect(detail.digest).to eq(digest)
        expect(detail.media_type).to eq('application/vnd.oci.image.index.v1+json')
        expect(detail.tags).to eq(%w[latest 1.2.3])
        expect(detail.children_count).to eq(1)
        expect(detail.children.first).to include('architecture' => 'amd64', 'os' => 'linux')
      end

      it 'keeps a null annotations map apart from an empty one', :aggregate_failures do
        stub_manifest(body: manifest_response.merge('annotations' => {}).to_json)
        expect(perform.annotations).to eq({})

        stub_manifest(body: manifest_response.merge('annotations' => nil).to_json)
        expect(perform.annotations).to be_nil
      end

      it 'reads under the oci images segment for an oci repository' do
        format_oci = 'oci'
        url = "#{repository_url}/#{format_oci}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}"
        request = stub_request(:get, url).to_return(status: 200, body: manifest_response.to_json, headers: json_headers)

        client.manifest(slug: slug, repository_name: name, format: format_oci, image_id: image_id, digest: digest)

        expect(request).to have_been_requested
      end

      it "serves a remote repository's contractually-empty readings without inventing values",
        :aggregate_failures do
        remote = manifest_response.merge(
          'annotations' => nil, 'children' => [], 'parent_digests' => [], 'referrers_count' => 0
        )
        stub_manifest(body: remote.to_json)

        detail = perform

        expect(detail.annotations).to be_nil
        expect(detail.children).to eq([])
        expect(detail.parent_digests).to eq([])
        expect(detail.referrers_count).to eq(0)
      end
    end

    context 'when AR returns 404' do
      it 'returns nil rather than raising, and reports nothing to error tracking', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_manifest(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises rather than resolving a hollow manifest present' do
        stub_manifest(body: '{}')

        expect { perform }.to raise_error(described_class::UnavailableError)
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        400 | ArtifactRegistry::Client::ApiError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope status', :aggregate_failures do
          stub_manifest(status: status, body: error_envelope(request_id: 'req-manifest-id').to_json)

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.status).to eq(status)
            expect(error.request_id).to eq('req-manifest-id')
          end
        end
      end
    end

    context 'when the repository is a package format' do
      let(:format) { 'maven' }

      it 'raises ArgumentError without contacting AR', :aggregate_failures do
        request = stub_request(:get, %r{#{Regexp.escape(base_url)}})

        expect { perform }.to raise_error(ArgumentError, /format must be one of/)
        expect(request).not_to have_been_requested
      end
    end

    # image_id and digest are user-supplied deep-link values, so a malformed one resolves nil like
    # a real 404 rather than raising, exposing no id-syntax oracle -- the single-read rule.
    context 'when the image id or digest is blank or a bare dot-segment' do
      where(:image_id, :digest) do
        nil        | "sha256:#{'1' * 64}"
        ''         | "sha256:#{'1' * 64}"
        '.'        | "sha256:#{'1' * 64}"
        '..'       | "sha256:#{'1' * 64}"
        'img'      | nil
        'img'      | ''
        'img'      | '.'
        'img'      | '..'
      end

      with_them do
        it 'resolves nil without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(base_url)}})

          expect(perform).to be_nil
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when slug or repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        nil        | 'my-repo'
        '.'        | 'my-repo'
        'my-group' | nil
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError, since a structural segment cannot resolve to not-found', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(base_url)}})

          expect { perform }.to raise_error(ArgumentError)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the digest and image id contain path separators' do
      let(:image_id) { 'a/b' }
      let(:digest) { 'sha256:x/y' }

      it 'percent-encodes each segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded = "#{format}/images/a%2Fb/manifests/sha256%3Ax%2Fy"
        encoded_request = stub_request(:get, "#{repository_url}/#{encoded}")
          .to_return(status: 200, body: manifest_response.to_json, headers: json_headers)
        traversed = stub_request(:get, "#{repository_url}/#{format}/images/a/b/manifests/sha256:x/y")

        perform

        expect(encoded_request).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#manifest_referrers' do
    let(:format) { 'docker' }
    let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:digest) { "sha256:#{'1' * 64}" }
    let(:request_url) do
      "#{repository_url}/#{format}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}/referrers"
    end

    # Every referrers row is itself a manifest-list element.
    let(:referrer_response) do
      {
        'id' => 'r1000-0000-0000-0000-000000000000',
        'digest' => "sha256:#{'a' * 64}",
        'media_type' => 'application/vnd.oci.image.manifest.v1+json',
        'artifact_type' => 'application/vnd.example.sbom',
        'subject_digest' => digest,
        'size' => 512,
        'created_at' => '2026-07-04T09:15:00Z'
      }
    end

    let(:list_response) { [referrer_response] }

    def perform_with(**arguments)
      client.manifest_referrers(
        slug: slug, repository_name: name, format: format, image_id: image_id, digest: digest, **arguments
      )
    end

    def perform
      perform_with
    end

    def stub_referrers(body:, status: 200, headers: json_headers, query: nil)
      request = stub_request(:get, request_url)
      request = request.with(query: query) if query
      request.to_return(status: status, body: body, headers: headers)
    end

    context 'when AR returns a page of referrers' do
      it 'reads the referrers of the manifest and returns Manifest rows on a Page', :aggregate_failures do
        request = stub_referrers(body: list_response.to_json)

        page = perform

        expect(request).to have_been_requested
        expect(page).to be_a(ArtifactRegistry::Page)
        expect(page.nodes).to all(be_a(ArtifactRegistry::Manifest))
        expect(page.nodes.first.subject_digest).to eq(digest)
      end

      it "returns an empty page for a manifest with no referrers, and for a remote repository" do
        stub_referrers(body: [].to_json)

        expect(perform.nodes).to eq([])
      end

      it 'reads under the oci images segment for an oci repository' do
        format_oci = 'oci'
        url = "#{repository_url}/#{format_oci}/images/#{image_id}/manifests/#{ERB::Util.url_encode(digest)}/referrers"
        request = stub_request(:get, url).to_return(status: 200, body: list_response.to_json, headers: json_headers)

        client.manifest_referrers(
          slug: slug, repository_name: name, format: format_oci, image_id: image_id, digest: digest
        )

        expect(request).to have_been_requested
      end
    end

    context 'with keyset parameters' do
      it 'forwards limit and cursor when the caller passes them' do
        request = stub_referrers(body: list_response.to_json, query: { limit: '20', cursor: 'abc' })

        perform_with(limit: 20, cursor: 'abc')

        expect(request).to have_been_requested
      end

      it 'sends no query string when the caller passes neither' do
        stub_referrers(body: list_response.to_json)

        perform

        expect(a_request(:get, request_url).with { |req| req.uri.query.blank? }).to have_been_made
      end
    end

    context 'when parsing the Link header for cursors' do
      it 'reads the next and prev cursors from the Link header onto the Page', :aggregate_failures do
        next_url = "#{request_url}?limit=20&cursor=#{next_cursor}"
        prev_url = "#{request_url}?limit=20&cursor=#{prev_cursor}"
        stub_referrers(
          body: list_response.to_json,
          headers: json_headers.merge('Link' => %(<#{next_url}>; rel="next", <#{prev_url}>; rel="prev"))
        )

        page = perform

        expect(page.next_cursor).to eq(next_cursor)
        expect(page.prev_cursor).to eq(prev_cursor)
      end

      it 'leaves both cursors nil when the response carries no Link header', :aggregate_failures do
        stub_referrers(body: list_response.to_json)

        page = perform

        expect(page.next_cursor).to be_nil
        expect(page.prev_cursor).to be_nil
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises rather than returning a page over a non-array body' do
        stub_referrers(body: '{}')

        expect { perform }.to raise_error(described_class::UnavailableError)
      end

      it 'raises rather than mapping an array whose entries are not Hashes' do
        stub_referrers(body: '["oops"]')

        expect { perform }.to raise_error(described_class::UnavailableError)
      end
    end

    context 'when AR returns 404 for an unknown digest' do
      it 'returns nil and logs the drift, carrying both the image id and the digest', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_referrers(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(instance_of(described_class::ApiError), hash_including(id: image_id, digest: digest))
      end
    end

    context 'when the repository is a package format' do
      let(:format) { 'npm' }

      it 'raises ArgumentError without contacting AR', :aggregate_failures do
        request = stub_request(:get, %r{#{Regexp.escape(base_url)}})

        expect { perform }.to raise_error(ArgumentError, /format must be one of/)
        expect(request).not_to have_been_requested
      end
    end

    # The image id and digest are the same user-supplied deep-link pair #manifest resolves nil for,
    # so this read shares the not-found semantics rather than raising -- no id-syntax oracle.
    context 'when the image id or digest is blank or a bare dot-segment' do
      where(:image_id, :digest) do
        nil   | "sha256:#{'1' * 64}"
        ''    | "sha256:#{'1' * 64}"
        '.'   | "sha256:#{'1' * 64}"
        '..'  | "sha256:#{'1' * 64}"
        'img' | nil
        'img' | ''
        'img' | '.'
        'img' | '..'
      end

      with_them do
        it 'resolves nil without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(base_url)}})

          expect(perform).to be_nil
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when slug or repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        nil        | 'my-repo'
        '.'        | 'my-repo'
        'my-group' | nil
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError, since a structural segment cannot resolve to not-found', :aggregate_failures do
          request = stub_request(:get, %r{#{Regexp.escape(base_url)}})

          expect { perform }.to raise_error(ArgumentError)
          expect(request).not_to have_been_requested
        end
      end
    end
  end

  describe '#create_repository' do
    let(:perform) { client.create_repository(slug: slug, name: name, format: 'maven') }
    let(:http_method) { :post }
    let(:request_url) { repositories_url }

    context 'when AR returns 201 with the created repository' do
      it 'POSTs the full body, attaches the Bearer credential, and returns the created Repository',
        :aggregate_failures do
        request = stub_request(:post, repositories_url)
          .with(
            body: {
              name: name,
              format: 'maven',
              kind: 'hosted',
              visibility: 'private',
              description: 'A hosted Maven repository'
            },
            headers: { 'Authorization' => "Bearer #{token}" }
          )
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)

        result = client.create_repository(
          slug: slug,
          name: name,
          format: 'maven',
          kind: 'hosted',
          visibility: 'private',
          description: 'A hosted Maven repository'
        )

        expect(result).to be_a(ArtifactRegistry::Repository)
        expect(result.name).to eq(name)
        expect(request).to have_been_requested
      end

      it 'omits the optional fields the caller did not provide' do
        request = stub_request(:post, repositories_url)
          .with(body: { name: name, format: 'maven' })
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)

        client.create_repository(slug: slug, name: name, format: 'maven')

        expect(request).to have_been_requested
      end
    end

    context 'when the caller supplies remote settings' do
      let(:settings) do
        { url: 'https://upstream.example.test', cache_validity_hours: 24,
          credentials: { username: 'upstream-user', password: 'upstream-secret' } }
      end

      it 'sends the settings object through without interpreting it' do
        request = stub_request(:post, repositories_url)
          .with(body: { name: name, format: 'maven', kind: 'remote', settings: settings })
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)

        client.create_repository(slug: slug, name: name, format: 'maven', kind: 'remote', settings: settings)

        expect(request).to have_been_requested
      end

      it 'keeps the settings object when the other optional fields are absent, rather than compacting it away' do
        request = stub_request(:post, repositories_url)
          .with(body: { name: name, format: 'maven', kind: 'remote',
                        settings: { url: 'https://upstream.example.test' } })
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)

        client.create_repository(slug: slug, name: name, format: 'maven', kind: 'remote',
          settings: { url: 'https://upstream.example.test' })

        expect(request).to have_been_requested
      end

      it 'does not reach inside the settings object, so a nil nested in it survives as JSON null' do
        request = stub_request(:post, repositories_url)
          .with(body: '{"name":"my-repo","format":"maven","kind":"remote","settings":' \
                  '{"url":"https://upstream.example.test","credentials":null}}')
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)

        client.create_repository(slug: slug, name: name, format: 'maven', kind: 'remote',
          settings: { url: 'https://upstream.example.test', credentials: nil })

        expect(request).to have_been_requested
      end
    end

    context 'when settings and kind disagree' do
      it 'refuses a settings object on a create AR resolves to hosted, without contacting AR', :aggregate_failures do
        request = stub_request(:post, repositories_url)

        settings = { url: 'https://upstream.example.test' }

        expect { client.create_repository(slug: slug, name: name, format: 'maven', settings: settings) }
          .to raise_error(ArgumentError, /only accepted for a remote repository/)
        expect(token_exchange).not_to have_received(:token_for)
        expect(request).not_to have_been_requested
      end

      it 'refuses a remote create that carries no settings, without contacting AR', :aggregate_failures do
        request = stub_request(:post, repositories_url)

        expect { client.create_repository(slug: slug, name: name, format: 'maven', kind: 'remote') }
          .to raise_error(ArgumentError, /required for a remote repository/)
        expect(token_exchange).not_to have_received(:token_for)
        expect(request).not_to have_been_requested
      end
    end

    context 'when the slug contains a path separator' do
      let(:slug) { 'grp/x' }

      it 'percent-encodes the slug segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:post, "#{base_url}/api/v1/grp%2Fx/repositories")
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)
        traversed = stub_request(:post, "#{base_url}/api/v1/grp/x/repositories")

        client.create_repository(slug: slug, name: name, format: 'maven')

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when slug is blank or a bare dot-segment' do
      where(:slug) { [nil, '..'] }

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { client.create_repository(slug: slug, name: name, format: 'maven') }
            .to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when name is a bare dot-segment' do
      where(:name) { ['.', '..'] }

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:post, repositories_url)

          expect { client.create_repository(slug: slug, name: name, format: 'maven') }
            .to raise_error(ArgumentError, /must not be a bare/)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when name contains dot segments without being one' do
      let(:name) { '../evil' }

      it 'sends the name through in the body rather than rejecting it' do
        request = stub_request(:post, repositories_url)
          .with(body: { name: name, format: 'maven' })
          .to_return(status: 201, body: repository_response.to_json, headers: json_headers)

        client.create_repository(slug: slug, name: name, format: 'maven')

        expect(request).to have_been_requested
      end
    end

    context 'when a required body field is blank' do
      where(:name, :format) do
        ''         | 'maven'
        nil        | 'maven'
        'my-repo'  | ''
        'my-repo'  | nil
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          request = stub_request(:post, repositories_url)

          expect { client.create_repository(slug: slug, name: name, format: format) }
            .to raise_error(ArgumentError, /is required/)
          expect(token_exchange).not_to have_received(:token_for)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 201, body: '[]', body_class: 'Array'
    end

    context 'when AR returns a mutation validation error' do
      it 'raises ApiError carrying the envelope code, message, status, and request_id', :aggregate_failures do
        stub_request(:post, repositories_url)
          .to_return(
            status: 422,
            body: error_envelope(code: 'unprocessable', message: 'name is taken', request_id: 'req-create').to_json,
            headers: json_headers
          )

        expect { client.create_repository(slug: slug, name: name, format: 'maven') }
          .to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(422)
            expect(error.code).to eq('unprocessable')
            expect(error.message).to include('name is taken')
            expect(error.request_id).to eq('req-create')
          end
      end
    end

    context 'when AR returns 404 (the slug did not resolve to a namespace at AR)' do
      it 'raises ApiError rather than returning nil', :aggregate_failures do
        stub_request(:post, repositories_url)
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect { client.create_repository(slug: slug, name: name, format: 'maven') }
          .to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(404)
          end
      end
    end

    context 'when a transport failure occurs on the POST' do
      it 'does not retry and issues the POST exactly once', :aggregate_failures do
        stub_request(:post, repositories_url).to_timeout

        expect { client.create_repository(slug: slug, name: name, format: 'maven') }
          .to raise_error(described_class::UnavailableError)
        expect(a_request(:post, repositories_url)).to have_been_made.once
      end
    end
  end

  describe '#update_repository' do
    let(:perform) { client.update_repository(slug: slug, name: name, visibility: 'public') }
    let(:http_method) { :patch }
    let(:request_url) { repository_url }

    context 'when AR returns 200 with the updated repository' do
      it 'PATCHes only the mutable fields, attaches the Bearer credential, and returns the updated Repository',
        :aggregate_failures do
        request = stub_request(:patch, repository_url)
          .with(
            body: { visibility: 'public', description: 'Now public' },
            headers: { 'Authorization' => "Bearer #{token}" }
          )
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        result = client.update_repository(slug: slug, name: name, visibility: 'public', description: 'Now public')

        expect(result).to be_a(ArtifactRegistry::Repository)
        expect(request).to have_been_requested
      end

      it 'sends only the mutable fields the caller provided' do
        request = stub_request(:patch, repository_url)
          .with(body: { visibility: 'public' })
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, visibility: 'public')

        expect(request).to have_been_requested
      end

      it 'sends an explicit nil description as JSON null rather than omitting it' do
        request = stub_request(:patch, repository_url)
          .with(body: '{"description":null}')
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, description: nil)

        expect(request).to have_been_requested
      end
    end

    context 'when the caller supplies remote settings' do
      it 'sends the settings object as the only field, so settings alone is a complete update' do
        settings = { url: 'https://upstream.example.test', cache_validity_hours: 24 }
        request = stub_request(:patch, repository_url)
          .with(body: { settings: settings })
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, settings: settings)

        expect(request).to have_been_requested
      end

      it 'sends the settings object beside the common fields' do
        request = stub_request(:patch, repository_url)
          .with(body: { visibility: 'public', settings: { url: 'https://upstream.example.test' } })
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, visibility: 'public',
          settings: { url: 'https://upstream.example.test' })

        expect(request).to have_been_requested
      end

      it 'omits the credentials key the settings object carries none of, leaving the stored values alone' do
        request = stub_request(:patch, repository_url)
          .with(body: '{"settings":{"cache_validity_hours":24}}')
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, settings: { cache_validity_hours: 24 })

        expect(request).to have_been_requested
      end

      it 'sends a credentials object the settings object carries, replacing the stored values' do
        request = stub_request(:patch, repository_url)
          .with(body: '{"settings":{"credentials":{"auth_token":"upstream-token"}}}')
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, settings: { credentials: { auth_token: 'upstream-token' } })

        expect(request).to have_been_requested
      end

      it 'sends an explicit nil credentials as JSON null, which clears the stored values' do
        request = stub_request(:patch, repository_url)
          .with(body: '{"settings":{"credentials":null}}')
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, settings: { credentials: nil })

        expect(request).to have_been_requested
      end

      it 'refuses an explicit nil settings, which AR rejects, without contacting AR', :aggregate_failures do
        request = stub_request(:patch, repository_url)

        expect { client.update_repository(slug: slug, name: name, settings: nil) }
          .to raise_error(ArgumentError, /settings must not be nil/)
        expect(token_exchange).not_to have_received(:token_for)
        expect(request).not_to have_been_requested
      end

      it 'sends an empty settings object rather than reading it as no field at all' do
        request = stub_request(:patch, repository_url)
          .with(body: '{"settings":{}}')
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)

        client.update_repository(slug: slug, name: name, settings: {})

        expect(request).to have_been_requested
      end
    end

    context 'when the caller provides no mutable field' do
      it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
        request = stub_request(:patch, repository_url)

        expect { client.update_repository(slug: slug, name: name) }
          .to raise_error(ArgumentError, /at least one mutable field is required/)
        expect(token_exchange).not_to have_received(:token_for)
        expect(request).not_to have_been_requested
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '"nope"', body_class: 'String'
    end

    context 'when the name contains path traversal characters' do
      let(:name) { '../evil' }

      it 'percent-encodes the name segment so it cannot traverse', :aggregate_failures do
        encoded = stub_request(:patch, "#{base_url}/api/v1/#{slug}/repositories/..%2Fevil")
          .to_return(status: 200, body: repository_response.to_json, headers: json_headers)
        traversed = stub_request(:patch, "#{base_url}/api/v1/#{slug}/evil")

        client.update_repository(slug: slug, name: name, visibility: 'public')

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when slug or name is blank or a bare dot-segment' do
      where(:slug, :name) do
        ''         | 'my-repo'
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { client.update_repository(slug: slug, name: name, visibility: 'public') }
            .to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when AR returns 404' do
      it 'raises ApiError (a genuine not-found), unlike the idempotent delete', :aggregate_failures do
        stub_ar_patch(status: 404, body: error_envelope(code: 'not_found', request_id: 'req-404').to_json)

        expect { client.update_repository(slug: slug, name: name, visibility: 'public') }
          .to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(404)
            expect(error.request_id).to eq('req-404')
          end
      end
    end

    context 'when AR returns a mutation validation error' do
      it 'raises ApiError carrying the envelope', :aggregate_failures do
        stub_ar_patch(status: 422, body: error_envelope(code: 'unprocessable', message: 'invalid update').to_json)

        expect { client.update_repository(slug: slug, name: name, description: 'x') }
          .to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(422)
            expect(error.message).to include('invalid update')
          end
      end
    end

    context 'when a transport failure occurs on the PATCH' do
      it 'does not retry and issues the PATCH exactly once', :aggregate_failures do
        stub_request(:patch, repository_url).to_timeout

        expect { client.update_repository(slug: slug, name: name, visibility: 'public') }
          .to raise_error(described_class::UnavailableError)
        expect(a_request(:patch, repository_url)).to have_been_made.once
      end
    end
  end

  describe '#delete_repository' do
    subject(:result) { client.delete_repository(slug: slug, name: name) }

    context 'when AR returns 204' do
      it 'issues a destructive DELETE with the Bearer credential and returns true', :aggregate_failures do
        request = stub_request(:delete, repository_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" }, query: { destructive: 'true' })
          .to_return(status: 204, body: '', headers: json_headers)

        expect(result).to be(true)
        expect(request).to have_been_requested
      end
    end

    context 'when AR returns 202 because the repository still held artifacts' do
      it 'returns true' do
        stub_ar_delete(status: 202)

        expect(result).to be(true)
      end
    end

    context 'when AR answers another 2xx' do
      it 'raises UnavailableError rather than reading it as a delete' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_delete(status: 200, body: '{}')

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when AR returns 404 (idempotent delete)' do
      it 'returns true without a report when the envelope confirms the not-found', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_delete(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(result).to be(true)
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end

      it 'raises ApiError when the 404 body is empty', :aggregate_failures do
        stub_ar_delete(status: 404, body: '')

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to be_nil
        end
      end

      it 'raises ApiError when an intermediary returns an HTML 404 with no error envelope' do
        stub_request(:delete, repository_url)
          .with(query: { destructive: 'true' })
          .to_return(status: 404, body: '<html>404 Not Found</html>', headers: { 'Content-Type' => 'text/html' })

        expect { result }.to raise_error(described_class::ApiError)
      end
    end

    context 'when AR returns 409' do
      it 'raises ApiError without a report rather than treating it as a successful delete', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_delete(status: 409, body: error_envelope(code: 'conflict', message: 'not empty').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(409)
          expect(error.message).to include('not empty')
        end
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end
    end

    context 'when AR returns 400 because the delete contract no longer accepts the request' do
      it 'reports the rejection to error tracking and raises ApiError', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_delete(
          status: 400,
          body: error_envelope(code: 'bad_request', message: 'destructive is required', request_id: 'req-400').to_json
        )

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.code).to eq('bad_request')
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError),
          hash_including(url: base_url, method: :delete, status: 400, code: 'bad_request', request_id: 'req-400',
            slug: slug)
        )
      end
    end

    context 'when the name contains a path separator' do
      let(:name) { 'evil/segment' }

      it 'percent-encodes the name segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{slug}/repositories/evil%2Fsegment")
          .with(query: { destructive: 'true' })
          .to_return(status: 204, body: '', headers: json_headers)
        traversed = stub_request(:delete, "#{base_url}/api/v1/#{slug}/evil/segment")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when slug or name is blank or a bare dot-segment' do
      where(:slug, :name) do
        ''         | 'my-repo'
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      # DELETE left faraday-retry's allowlist so a replayed eviction cannot report 404 for a delete
      # that succeeded. The cost lands here: a lost response on a successful repository delete now
      # raises instead of being recovered by the replay's 404.
      it 'does not retry and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, repository_url).with(query: { destructive: 'true' }).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, repository_url).with(query: { destructive: 'true' })).to have_been_made.once
      end
    end
  end

  describe '#bulk_delete_artifacts' do
    let(:format) { 'maven' }
    let(:collection) { 'packages' }
    let(:bulk_delete_url) { "#{repository_url}/#{format}/#{collection}/bulk_delete" }

    subject(:result) { client.bulk_delete_artifacts(slug: slug, repository_name: name, format: format) }

    def stub_bulk_delete(status:, body: '')
      stub_request(:post, bulk_delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the batch' do
      where(:format, :collection) do
        'maven'  | 'packages'
        'npm'    | 'packages'
        'docker' | 'images'
        'oci'    | 'images'
      end

      with_them do
        # The body is pinned as a literal: the contract closes additionalProperties on the
        # whole-collection selector, so a stray key is a 400 rather than a wider delete.
        it 'posts the whole-collection selector to the route the format selects, and returns nil',
          :aggregate_failures do
          request = stub_request(:post, bulk_delete_url)
            .with(body: '{"delete_all":true}', headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 202, body: '', headers: json_headers)

          expect(result).to be_nil
          expect(request).to have_been_requested
        end
      end
    end

    context 'when the job backend cannot take the enqueue (503)' do
      # Each collection declares its own 503 in the contract, so both are asserted rather than one
      # standing in for the other. The name stops at what a 503 reports, because the same
      # UnavailableError also covers a lost response, where re-sending the selector is not the
      # recovery: the caller has to re-read instead.
      where(:format, :collection) do
        'maven'  | 'packages'
        'docker' | 'images'
      end

      with_them do
        it 'raises UnavailableError, the enqueue refused and nothing applied' do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_bulk_delete(status: 503, body: error_envelope(code: 'service_unavailable').to_json)

          expect { result }.to raise_error(described_class::UnavailableError)
        end
      end
    end

    context 'when AR returns a mapped 4xx' do
      # 404 is the virtual-repository answer, since a virtual repository owns no artifact rows to
      # act on; 400 is what the closed selector schema answers for a stray body key. Neither may
      # become an absence: this method takes no nil_on_missing wrapper, and adding one would turn a
      # whole-collection delete that never happened into a success.
      where(:status) { [400, 404] }

      with_them do
        it 'raises ApiError carrying the status rather than returning nil', :aggregate_failures do
          stub_bulk_delete(status: status, body: error_envelope(request_id: 'req-bulk-id').to_json)

          expect { result }.to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(status)
            expect(error.request_id).to eq('req-bulk-id')
          end
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      # The one branch of raise_error the other examples miss: these raise directly, with no error
      # tracking. AuthorizationError descends from Error and not from ApiError, so a caller
      # rescuing ApiError to report a failed delete does not catch it; both halves are pinned here
      # because the mutations built on this method depend on them.
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports no AR outage', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_bulk_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { result }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_bulk_delete(status: 200, body: '{}')

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the format is in neither the package nor the image list' do
      let(:format) { 'conda' }

      it 'raises ArgumentError naming every served format, before any request', :aggregate_failures do
        expect { result }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
        expect(token_exchange).not_to have_received(:token_for)
        expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
      end
    end

    context 'when slug or the repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        ''         | 'my-repo'
        'my-group' | ''
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when the slug and the repository name contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{collection}/bulk_delete"
        encoded = stub_request(:post, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:post,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{collection}/bulk_delete")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI or the body', :aggregate_failures do
        stub_bulk_delete(status: 202)

        result

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(
          a_request(:post, bulk_delete_url)
            .with { |req| req.uri.to_s.exclude?(token) && req.body.to_s.exclude?(token) }
        ).to have_been_made
      end

      it 'redacts a credential AR echoes in an error envelope, in both the raised and the logged error',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        echoed = "rejected: Authorization: Bearer #{jwt_credential}"
        stub_bulk_delete(status: 503, body: error_envelope(message: echoed).to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).not_to include(jwt_credential)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
          expect(logged.message).not_to include(jwt_credential)
        end
      end
    end

    context 'when a transport failure occurs on the POST' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry the eviction and issues the POST exactly once', :aggregate_failures do
        stub_request(:post, bulk_delete_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, bulk_delete_url)).to have_been_made.once
      end
    end
  end

  shared_examples 'a single container artifact delete' do |id_argument:|
    def stub_member_delete(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the delete' do
      where(:format) { %w[docker oci] }

      with_them do
        it 'issues the delete under the image the caller named, and returns nil', :aggregate_failures do
          request = stub_request(:delete, delete_url)
            .with(headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 202, body: '', headers: json_headers)

          expect(perform).to be_nil
          expect(request).to have_been_requested
        end
      end

      it 'treats the empty body as the whole outcome rather than parsing a payload', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_member_delete(status: 202)

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end
    end

    context 'when the segment resolves to nothing (404)' do
      where(:member_id) do
        [
          ref(:resolvable_member_id),
          ref(:malformed_member_id)
        ]
      end

      with_them do
        it 'raises ApiError carrying the 404 rather than a validation error', :aggregate_failures do
          stub_member_delete(status: 404, body: error_envelope(code: 'not_found').to_json)

          expect { perform }.to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(404)
            expect(error.code).to eq('not_found')
          end
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports no AR outage', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_member_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { perform }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR cannot answer the delete (500 and 503)' do
      where(:status) { [500, 503] }

      with_them do
        it 'raises UnavailableError and redacts an echoed credential in both errors', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          echoed = "rejected: Authorization: Bearer #{jwt_credential}"
          stub_member_delete(status: status, body: error_envelope(message: echoed).to_json)

          expect { perform }.to raise_error(described_class::UnavailableError) do |error|
            expect(error.message).to include('Bearer [REDACTED]')
            expect(error.message).not_to include(jwt_credential)
          end
          expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
            expect(logged.message).not_to include(jwt_credential)
          end
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_member_delete(status: 200, body: '{}')

        expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the format is not a container format' do
      where(:format) { %w[maven npm conda] }

      with_them do
        it 'raises ArgumentError naming only the container formats, before any request', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError, 'format must be one of: docker, oci')
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end
    end

    context 'when a path segment is blank or a bare dot-segment' do
      where(:slug, :name, :image_id, :member_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000' | ref(:resolvable_member_id)
        'my-group' | ''        | 'a1b2c3d4-0000-0000-0000-000000000000' | ref(:resolvable_member_id)
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000' | ref(:resolvable_member_id)
        'my-group' | 'my-repo' | ''                                     | ref(:resolvable_member_id)
        'my-group' | 'my-repo' | '..'                                   | ref(:resolvable_member_id)
        'my-group' | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000' | nil
        'my-group' | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000' | ''
        'my-group' | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end

      context 'when the member segment is blank' do
        let(:member_id) { '' }

        it "names #{id_argument} and sends nothing at the sub-collection route", :aggregate_failures do
          request = stub_request(:delete, "#{repository_url}/#{format}/images/#{image_id}/#{sub_collection}/")

          expect { perform }.to raise_error(ArgumentError, "#{id_argument} is required")
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the path segments contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:image_id) { 'i/d' }
      let(:member_id) { 'a/b' }

      it 'percent-encodes every path segment so a value cannot smuggle extra segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/images/i%2Fd/#{sub_collection}/a%2Fb"
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:delete,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/images/i/d/#{sub_collection}/a/b")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_member_delete(status: 202)

        perform

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end
  end

  describe '#delete_manifest' do
    let(:format) { 'docker' }
    let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) do
      "#{repository_url}/#{format}/images/#{image_id}/#{sub_collection}/#{ERB::Util.url_encode(member_id)}"
    end

    let(:sub_collection) { 'manifests' }
    let(:resolvable_member_id) { "sha256:#{'1' * 64}" }
    let(:malformed_member_id) { 'not-a-digest' }
    let(:member_id) { resolvable_member_id }
    let(:parents) { ["sha256:#{'a' * 64}", "sha256:#{'b' * 64}"] }

    def perform
      client.delete_manifest(
        slug: slug, repository_name: name, format: format, image_id: image_id, digest: member_id
      )
    end

    def stub_manifest_conflict(details)
      body = { error: { code: 'conflict', message: 'the manifest is indexed by another manifest',
                        request_id: 'req-conflict-id', details: details } }

      stub_request(:delete, delete_url).to_return(status: 409, body: body.to_json, headers: json_headers)
    end

    it_behaves_like 'a single container artifact delete', id_argument: :digest

    context 'when another manifest indexes the target (409)' do
      it 'raises ApiError carrying the blocking digests rather than stripping them', :aggregate_failures do
        stub_manifest_conflict({ parents: parents })

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(409)
          expect(error.code).to eq('conflict')
          expect(error.details).to eq({ 'parents' => parents })
        end
      end

      it 'carries a non-canonical digest too, which a UUID predicate would silently drop' do
        non_canonical = ["sha512:#{'C' * 128}"]
        stub_manifest_conflict({ parents: non_canonical })

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.details).to eq({ 'parents' => non_canonical })
        end
      end

      it 'drops a parents entry that is not digest-shaped, since details bypasses the redaction' do
        stub_manifest_conflict({ parents: [parents.first, "Bearer #{jwt_credential}"] })

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.details).to be_nil
        end
      end

      where(:details) { [{}, { parents: [] }, { other_key: parents }] }

      with_them do
        it 'raises without inventing digests when the details carry none', :aggregate_failures do
          stub_manifest_conflict(details)

          expect { perform }.to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(409)
            expect(error.details).to be_nil
          end
        end
      end
    end
  end

  describe '#delete_container_tag' do
    let(:format) { 'docker' }
    let(:image_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) do
      "#{repository_url}/#{format}/images/#{image_id}/#{sub_collection}/#{ERB::Util.url_encode(member_id)}"
    end

    let(:sub_collection) { 'tags' }
    let(:resolvable_member_id) { 'v1.2.3' }
    let(:malformed_member_id) { '-leading-hyphen' }
    let(:member_id) { resolvable_member_id }

    def perform
      client.delete_container_tag(
        slug: slug, repository_name: name, format: format, image_id: image_id, tag_name: member_id
      )
    end

    it_behaves_like 'a single container artifact delete', id_argument: :tag_name
  end

  describe '#delete_artifact' do
    let(:format) { 'maven' }
    let(:collection) { 'packages' }
    let(:artifact_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) { "#{repository_url}/#{format}/#{collection}/#{artifact_id}" }

    subject(:result) do
      client.delete_artifact(slug: slug, repository_name: name, format: format, id: artifact_id)
    end

    def stub_artifact_delete(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the delete' do
      where(:format, :collection) do
        'maven'  | 'packages'
        'npm'    | 'packages'
        'docker' | 'images'
        'oci'    | 'images'
      end

      with_them do
        it 'issues the delete for the id under the route the format selects, and returns nil',
          :aggregate_failures do
          request = stub_request(:delete, delete_url)
            .with(headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 202, body: '', headers: json_headers)

          expect(result).to be_nil
          expect(request).to have_been_requested
        end
      end
    end

    context 'when the artifact is already gone (404)' do
      # Unlike delete_repository, this takes no idempotence rescue: AR distinguishes a missing
      # artifact from an accepted delete, so the caller is told rather than shown a success.
      it 'raises ApiError carrying the status rather than resolving nil', :aggregate_failures do
        stub_artifact_delete(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports no AR outage', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_artifact_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { result }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR fails the delete (500)' do
      # The contract declares 500 on this route, and 500 is the one delete_artifact status that
      # reaches the logging path, so the logged half of the redaction is exercised here rather than
      # left to the bulk method.
      it 'raises UnavailableError and redacts an echoed credential in both errors', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        echoed = "rejected: Authorization: Bearer #{jwt_credential}"
        stub_artifact_delete(status: 500, body: error_envelope(message: echoed).to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).not_to include(jwt_credential)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
          expect(logged.message).not_to include(jwt_credential)
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_artifact_delete(status: 200, body: '{}')

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the format is in neither the package nor the image list' do
      let(:format) { 'conda' }

      it 'raises ArgumentError naming every served format, before any request', :aggregate_failures do
        expect { result }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
        expect(token_exchange).not_to have_received(:token_for)
        expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
      end
    end

    context 'when slug, the repository name, or the id is blank or a bare dot-segment' do
      where(:slug, :name, :artifact_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | ''        | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | ''
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end

      context 'when the id is blank' do
        let(:artifact_id) { '' }

        it 'sends nothing at the collection route, which a blank id would otherwise address' do
          request = stub_request(:delete, "#{repository_url}/#{format}/#{collection}/")

          expect { result }.to raise_error(ArgumentError)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug, the repository name, and the id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:artifact_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{collection}/a%2Fb"
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:delete,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{collection}/a/b")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_artifact_delete(status: 202)

        result

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      # The point of narrowing RETRY_OPTIONS[:methods]: a replayed eviction hits an artifact the
      # first attempt already removed, and AR's 404 would report a failure for a delete that worked.
      it 'does not retry the eviction and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end
  end

  shared_examples 'a single package artifact delete' do |id_argument:|
    let(:format) { 'maven' }
    let(:artifact_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) { "#{repository_url}/#{format}/#{collection}/#{artifact_id}" }

    def stub_single_delete(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the delete' do
      where(:format) { %w[maven npm] }

      with_them do
        it 'issues the delete under the format segment the caller passed, and returns nil',
          :aggregate_failures do
          request = stub_request(:delete, delete_url)
            .with(headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 202, body: '', headers: json_headers)

          expect(perform).to be_nil
          expect(request).to have_been_requested
        end
      end

      it 'treats the empty body as the whole outcome rather than parsing a payload',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_single_delete(status: 202)

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end
    end

    context 'when the artifact is already gone (404)' do
      it 'raises ApiError carrying the status rather than resolving nil', :aggregate_failures do
        stub_single_delete(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports no AR outage', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_single_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { perform }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR cannot answer the delete (500 and 503)' do
      where(:status) { [500, 503] }

      with_them do
        it 'raises UnavailableError and redacts an echoed credential in both errors',
          :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          echoed = "rejected: Authorization: Bearer #{jwt_credential}"
          stub_single_delete(status: status, body: error_envelope(message: echoed).to_json)

          expect { perform }.to raise_error(described_class::UnavailableError) do |error|
            expect(error.message).to include('Bearer [REDACTED]')
            expect(error.message).not_to include(jwt_credential)
          end
          expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
            expect(logged.message).not_to include(jwt_credential)
          end
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_single_delete(status: 200, body: '{}')

        expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the format is not a package format' do
      where(:format) { %w[docker oci conda] }

      with_them do
        it 'raises ArgumentError naming only the package formats, before any request',
          :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError, 'format must be one of: maven, npm')
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end
    end

    context 'when slug, the repository name, or the id is blank or a bare dot-segment' do
      where(:slug, :name, :artifact_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | ''        | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | ''
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end

      context 'when the id is blank' do
        let(:artifact_id) { '' }

        it "names #{id_argument} and sends nothing at the collection route", :aggregate_failures do
          request = stub_request(:delete, "#{repository_url}/#{format}/#{collection}/")

          expect { perform }.to raise_error(ArgumentError, "#{id_argument} is required")
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug, the repository name, and the id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:artifact_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{collection}/a%2Fb"
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:delete,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{collection}/a/b")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_single_delete(status: 202)

        perform

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end
  end

  describe '#delete_version' do
    let(:collection) { 'versions' }

    def perform
      client.delete_version(slug: slug, repository_name: name, format: format, version_id: artifact_id)
    end

    it_behaves_like 'a single package artifact delete', id_argument: :version_id
  end

  describe '#delete_file' do
    let(:collection) { 'files' }

    def perform
      client.delete_file(slug: slug, repository_name: name, format: format, file_id: artifact_id)
    end

    it_behaves_like 'a single package artifact delete', id_argument: :file_id
  end

  describe '#delete_npm_dist_tag' do
    let(:tag_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) { "#{repository_url}/npm/tags/#{tag_id}" }

    def perform
      client.delete_npm_dist_tag(slug: slug, repository_name: name, tag_id: tag_id)
    end

    def stub_dist_tag_delete(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the delete' do
      it 'issues the delete under the npm literal, and returns nil', :aggregate_failures do
        request = stub_request(:delete, delete_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" })
          .to_return(status: 202, body: '', headers: json_headers)

        expect(perform).to be_nil
        expect(request).to have_been_requested
      end

      it 'treats the empty body as the whole outcome rather than parsing a payload', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_dist_tag_delete(status: 202)

        expect(perform).to be_nil
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
      end
    end

    context 'when a caller tries to choose the format segment' do
      it 'accepts no format argument, so the segment cannot be steered off npm' do
        expect do
          client.delete_npm_dist_tag(slug: slug, repository_name: name, tag_id: tag_id, format: 'maven')
        end.to raise_error(ArgumentError, /unknown keyword: :format/)
      end
    end

    # Hosted-only route: AR answers 404 on a remote repository permanently (S17), and this
    # maps it like any other 404 because the client takes no kind.
    context 'when the tag is already gone (404)' do
      it 'raises ApiError carrying the status rather than resolving nil', :aggregate_failures do
        stub_dist_tag_delete(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports no AR outage', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_dist_tag_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { perform }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR cannot answer the delete (500 and 503)' do
      where(:status) { [500, 503] }

      with_them do
        it 'raises UnavailableError and redacts an echoed credential in both errors', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          echoed = "rejected: Authorization: Bearer #{jwt_credential}"
          stub_dist_tag_delete(status: status, body: error_envelope(message: echoed).to_json)

          expect { perform }.to raise_error(described_class::UnavailableError) do |error|
            expect(error.message).to include('Bearer [REDACTED]')
            expect(error.message).not_to include(jwt_credential)
          end
          expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
            expect(logged.message).not_to include(jwt_credential)
          end
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_dist_tag_delete(status: 200, body: '{}')

        expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when a path segment is blank or a bare dot-segment' do
      where(:slug, :name, :tag_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | ''        | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | ''
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end

      context 'when the tag id is blank' do
        let(:tag_id) { '' }

        it 'names tag_id in the error' do
          expect { perform }.to raise_error(ArgumentError, 'tag_id is required')
        end
      end
    end

    context 'when the path segments contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:tag_id) { 'a/b' }

      it 'percent-encodes every path segment so a value cannot smuggle extra segments', :aggregate_failures do
        encoded = stub_request(:delete, "#{base_url}/api/v1/grp%2Fx/repositories/evil%2Fsegment/npm/tags/a%2Fb")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:delete, "#{base_url}/api/v1/grp/x/repositories/evil/segment/npm/tags/a/b")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_dist_tag_delete(status: 202)

        perform

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end
  end

  describe '#dissociate_upstream_repository' do
    let(:format) { 'maven' }
    let(:association_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) { "#{repository_url}/#{format}/upstream_repositories/#{association_id}" }

    def perform
      client.dissociate_upstream_repository(
        slug: slug, repository_name: name, format: format, association_id: association_id
      )
    end

    def stub_dissociate(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR removes the association' do
      where(:format) { %w[maven npm docker oci] }

      with_them do
        it 'issues the delete under the format upstream_repositories member route and returns true',
          :aggregate_failures do
          request = stub_request(:delete, delete_url)
            .with(headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 204, body: '', headers: json_headers)

          expect(perform).to be(true)
          expect(request).to have_been_requested
        end
      end
    end

    context 'when the association is already gone (404)' do
      it 'returns true and reports the drift, covering a missing, non-virtual, or unseen repository',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_dissociate(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(perform).to be(true)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError),
          hash_including(method: :delete, code: 'not_found', status: 404, slug: slug,
            path: "api/v1/#{slug}/repositories/#{name}/#{format}/upstream_repositories/#{association_id}")
        )
      end

      it 'raises ApiError when the 404 body carries no error envelope', :aggregate_failures do
        stub_dissociate(status: 404, body: '')

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to be_nil
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports no AR outage', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_dissociate(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { perform }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
        end
      end
    end

    context 'when AR cannot answer the delete (500 and 503)' do
      where(:status) { [500, 503] }

      with_them do
        it 'raises UnavailableError and redacts an echoed credential', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          echoed = "rejected: Authorization: Bearer #{jwt_credential}"
          stub_dissociate(status: status, body: error_envelope(message: echoed).to_json)

          expect { perform }.to raise_error(described_class::UnavailableError) do |error|
            expect(error.message).to include('Bearer [REDACTED]')
            expect(error.message).not_to include(jwt_credential)
          end
        end
      end
    end

    context 'when AR answers a 2xx the contract does not allow' do
      where(:status) { [200, 202] }

      with_them do
        it 'raises UnavailableError rather than reading another 2xx as a removal' do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_dissociate(status: status, body: '{}')

          expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
        end
      end
    end

    context 'when the format is not an artifact format' do
      where(:format) { ['conda', 'helm', ''] }

      with_them do
        it 'raises ArgumentError naming the artifact formats, before any request', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end
    end

    context 'when slug, the repository name, or the association id is blank or a bare dot-segment' do
      where(:slug, :name, :association_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | ''        | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | ''
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end

      context 'when the association id is blank' do
        let(:association_id) { '' }

        it 'names association_id and sends nothing at the collection route', :aggregate_failures do
          request = stub_request(:delete, "#{repository_url}/#{format}/upstream_repositories/")

          expect { perform }.to raise_error(ArgumentError, 'association_id is required')
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the association id is not a UUID' do
      let(:association_id) { 'not-a-uuid' }

      it 'issues the delete rather than asserting a syntax the contract does not', :aggregate_failures do
        request = stub_dissociate(status: 204)

        expect(perform).to be(true)
        expect(request).to have_been_requested
      end
    end

    context 'when the slug, the repository name, and the association id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:association_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/upstream_repositories/a%2Fb"
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 204, body: '', headers: json_headers)
        traversed = stub_request(:delete,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/upstream_repositories/a/b")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_dissociate(status: 204)

        perform

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end
  end

  describe '#test_upstream_connection' do
    let(:test_url) { "#{repository_url}/test" }
    let(:http_method) { :post }
    let(:request_url) { test_url }
    let(:perform) { result }

    let(:test_response) do
      {
        'passed' => true,
        'http_status' => 200,
        'last_health_status' => 'healthy',
        'last_health_checked_at' => '2026-08-20T10:00:00Z'
      }
    end

    subject(:result) { client.test_upstream_connection(slug: slug, name: name) }

    def stub_ar_test(status:, body:)
      stub_request(:post, test_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR returns 200 with a verdict' do
      it 'POSTs to the repository test path with the Bearer credential and no body', :aggregate_failures do
        request = stub_request(:post, test_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" }) { |req| req.body.empty? }
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)

        expect(result).to be_a(ArtifactRegistry::ConnectionTestResult)
        expect(request).to have_been_requested
      end

      it 'sends no Content-Type, so AR sees no body rather than an empty JSON object' do
        stub_ar_test(status: 200, body: test_response.to_json)

        result

        expect(a_request(:post, test_url).with { |req| !req.headers.key?('Content-Type') }).to have_been_made
      end

      it 'returns the parsed verdict beside the stored health fields', :aggregate_failures do
        stub_ar_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(true)
        expect(result.http_status).to eq(200)
        expect(result.last_health_status).to eq('healthy')
        expect(result.last_health_checked_at).to eq(DateTime.iso8601('2026-08-20T10:00:00Z'))
      end
    end

    context 'when the probe found the upstream unreachable' do
      let(:test_response) do
        {
          'passed' => false,
          'http_status' => nil,
          'last_health_status' => 'healthy',
          'last_health_checked_at' => '2026-08-20T10:00:00Z'
        }
      end

      it 'returns the not-passed verdict rather than raising, and keeps the stored status AR reports',
        :aggregate_failures do
        stub_ar_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(false)
        expect(result.http_status).to be_nil
        expect(result.last_health_status).to eq('healthy')
      end
    end

    context 'when AR returns 200 without a verdict' do
      it 'raises UnavailableError rather than reporting an unreachable upstream', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_test(status: 200, body: test_response.except('passed').to_json)

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '[]', body_class: 'Array'
    end

    context 'when AR returns 404 (the route exists on remote repositories only)' do
      it 'raises ApiError rather than resolving nil, unlike the reads', :aggregate_failures do
        stub_ar_test(status: 404, body: error_envelope(code: 'not_found', request_id: 'req-test-404').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-test-404')
        end
      end
    end

    context 'when AR returns 400 because a body reached it' do
      it 'raises ApiError carrying the envelope', :aggregate_failures do
        stub_ar_test(status: 400, body: error_envelope(code: 'bad_request', message: 'body not allowed').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.message).to include('body not allowed')
        end
      end
    end

    context 'when AR returns 500 (a probe ran and its verdict could not be recorded)' do
      it 'raises UnavailableError attributed to the slug', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_test(status: 500, body: error_envelope(code: 'internal').to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.status).to eq(500)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when the name contains a path separator' do
      let(:name) { 'evil/segment' }

      it 'percent-encodes the name segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:post, "#{base_url}/api/v1/#{slug}/repositories/evil%2Fsegment/test")
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)
        traversed = stub_request(:post, "#{base_url}/api/v1/#{slug}/repositories/evil/segment/test")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when slug or name is blank or a bare dot-segment' do
      where(:slug, :name) do
        ''         | 'my-repo'
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when a transport failure occurs on the POST' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry the state-recording POST and issues it exactly once', :aggregate_failures do
        stub_request(:post, test_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, test_url)).to have_been_made.once
      end
    end
  end

  describe '#test_namespace_upstream_connection' do
    let(:connection_test_url) { "#{base_url}/api/v1/#{slug}/connection_test" }
    let(:http_method) { :post }
    let(:request_url) { connection_test_url }
    let(:perform) { result }

    let(:format) { 'maven' }
    let(:url) { 'https://upstream.example.test' }
    let(:credentials) { nil }

    let(:test_response) do
      { 'passed' => true, 'http_status' => 200 }
    end

    subject(:result) do
      client.test_namespace_upstream_connection(slug: slug, format: format, url: url, credentials: credentials)
    end

    def stub_ar_connection_test(status:, body:)
      stub_request(:post, connection_test_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR returns 200 with a verdict' do
      it 'POSTs the format and url body with the Bearer credential', :aggregate_failures do
        request = stub_request(:post, connection_test_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" }, body: { format: 'maven', url: url })
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)

        expect(result).to be_a(ArtifactRegistry::NamespaceConnectionTestResult)
        expect(request).to have_been_requested
      end

      it 'returns the parsed verdict', :aggregate_failures do
        stub_ar_connection_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(true)
        expect(result.http_status).to eq(200)
      end
    end

    context 'with credentials' do
      let(:credentials) { { username: 'octocat', password: 's3cret' } }

      it 'forwards them in the body' do
        request = stub_request(:post, connection_test_url)
          .with(body: { format: 'maven', url: url, credentials: { username: 'octocat', password: 's3cret' } })
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)

        result

        expect(request).to have_been_requested
      end
    end

    context 'without credentials' do
      it 'omits the credentials key rather than sending a null' do
        stub_ar_connection_test(status: 200, body: test_response.to_json)

        result

        expect(a_request(:post, connection_test_url).with { |req| req.body.exclude?('credentials') })
          .to have_been_made
      end
    end

    context 'when the probe found the upstream unreachable' do
      let(:test_response) { { 'passed' => false, 'http_status' => nil } }

      it 'returns the not-passed verdict rather than raising', :aggregate_failures do
        stub_ar_connection_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(false)
        expect(result.http_status).to be_nil
      end
    end

    context 'when AR returns 200 without a verdict' do
      it 'raises UnavailableError rather than reporting an unreachable upstream', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_connection_test(status: 200, body: test_response.except('passed').to_json)

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '[]', body_class: 'Array'
    end

    context 'when AR returns 400 because the url or body was rejected' do
      it 'raises ApiError carrying the envelope', :aggregate_failures do
        stub_ar_connection_test(status: 400, body: error_envelope(code: 'bad_request', message: 'url invalid').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.message).to include('url invalid')
        end
      end
    end

    context 'when AR returns 404 because the slug did not resolve' do
      it 'raises ApiError rather than resolving nil, unlike the reads', :aggregate_failures do
        stub_ar_connection_test(status: 404, body: error_envelope(code: 'not_found', request_id: 'req-ct-404').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
        end
      end
    end

    context 'when AR returns 500' do
      it 'raises UnavailableError attributed to the slug', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_connection_test(status: 500, body: error_envelope(code: 'internal').to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.status).to eq(500)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when the slug contains a path separator' do
      let(:slug) { 'evil/segment' }

      it 'percent-encodes the slug so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:post, "#{base_url}/api/v1/evil%2Fsegment/connection_test")
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)
        traversed = stub_request(:post, "#{base_url}/api/v1/evil/segment/connection_test")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when an argument is invalid' do
      where(:slug, :format, :url) do
        ''         | 'maven' | 'https://upstream.example.test'
        '..'       | 'maven' | 'https://upstream.example.test'
        'my-group' | 'gems'  | 'https://upstream.example.test'
        'my-group' | 'maven' | ''
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when a transport failure occurs on the POST' do
      before do
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
      end

      it 'does not retry the POST and issues it exactly once', :aggregate_failures do
        stub_request(:post, connection_test_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, connection_test_url)).to have_been_made.once
      end
    end
  end

  describe '#namespace' do
    let(:uuid) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:service_token) { 'ar-service-credential-value' }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: service_token) }
    let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{uuid}" }

    let(:service_client) do
      described_class.new(base_url: base_url, service_credential: service_credential, token_exchange: token_exchange)
    end

    let(:namespace_response) do
      {
        'id' => uuid,
        'slug' => 'my-group',
        'platform' => 'gitlab',
        'entity_type' => 'group',
        'entity_id' => '42',
        'status' => 'active',
        'created_at' => '2026-07-01T10:00:00Z'
      }
    end

    def stub_namespace_get(status:, body: '', headers: json_headers)
      stub_request(:get, namespace_url).to_return(status: status, body: body, headers: headers)
    end

    context 'when AR returns 200 with a namespace body' do
      it 'issues a GET with the service credential and returns a Namespace', :aggregate_failures do
        request = stub_request(:get, namespace_url)
          .with(headers: { described_class::SERVICE_TOKEN_HEADER => service_token })
          .to_return(status: 200, body: namespace_response.to_json, headers: json_headers)

        result = service_client.namespace(uuid: uuid)

        expect(result).to be_a(ArtifactRegistry::Namespace)
        expect(result.id).to eq(uuid)
        expect(result.status).to eq('active')
        expect(request).to have_been_requested
      end

      it 'does not consult the per-user token exchange', :aggregate_failures do
        stub_namespace_get(status: 200, body: namespace_response.to_json)

        service_client.namespace(uuid: uuid)

        expect(token_exchange).not_to have_received(:token_for)
      end
    end

    context 'when AR returns 404' do
      it 'returns nil and logs the uuid with the request identifiers, no credential', :aggregate_failures do
        logged = []
        allow(Gitlab::ErrorTracking).to receive(:log_exception) { |*args| logged << args }
        stub_namespace_get(status: 404, body: error_envelope(request_id: 'req-404').to_json)

        expect(service_client.namespace(uuid: uuid)).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError),
          { url: base_url, uuid: uuid, correlation_id: anything, request_id: 'req-404', status: 404 }
        )
        expect(logged.to_s).not_to include(service_token)
      end

      it 'reads request_id from the X-Request-Id header when the 404 body is empty' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_namespace_get(status: 404, body: '', headers: json_headers.merge('X-Request-Id' => 'req-header-404'))

        expect(service_client.namespace(uuid: uuid)).to be_nil
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError), hash_including(request_id: 'req-header-404')
        )
      end
    end

    context 'when AR returns 400 for a non-canonical uuid spelling' do
      it 'raises ApiError carrying the 400 status' do
        stub_namespace_get(status: 400, body: error_envelope(code: 'invalid_argument').to_json)

        expect { service_client.namespace(uuid: uuid) }
          .to raise_error(described_class::ApiError) { |e| expect(e.status).to eq(400) }
      end
    end

    it 'raises a credential error naming no principal, since both paths share the guard' do
      expect { described_class.new(base_url: base_url).namespace(uuid: uuid) }
        .to raise_error(described_class::AuthorizationError, 'No Artifact Registry credential was obtained')
    end

    # url_encode neutralizes separators, but not a blank or dot segment: those
    # would rewrite the request path itself.
    context 'when the uuid is blank or a dot segment' do
      where(:bad_uuid) { [nil, '', '.', '..'] }

      with_them do
        it 'raises ArgumentError before any credential is obtained', :aggregate_failures do
          request = stub_request(:get, %r{/api/gitlab/v1/namespaces})

          expect { service_client.namespace(uuid: bad_uuid) }.to raise_error(ArgumentError)
          expect(request).not_to have_been_requested
          expect(service_credential).not_to have_received(:token)
        end
      end
    end

    # A drift check that accepts an id-less body would report a namespace whose
    # every reader is nil as present.
    context 'when AR returns 200 without an id' do
      it 'raises UnavailableError rather than a namespace of nils', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_namespace_get(status: 200, body: '{}')

        expect { service_client.namespace(uuid: uuid) }
          .to raise_error(described_class::UnavailableError, /unexpected success response/)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(anything, hash_including(uuid: uuid))
      end
    end

    context 'when AR returns a bodiless 401' do
      it 'raises AuthorizationError carrying the X-Request-Id header value', :aggregate_failures do
        stub_namespace_get(status: 401, body: '', headers: json_headers.merge('X-Request-Id' => 'req-header-401'))

        expect { service_client.namespace(uuid: uuid) }.to raise_error(described_class::AuthorizationError) do |e|
          expect(e.request_id).to eq('req-header-401')
        end
      end
    end

    context 'when the service credential is absent (null default)' do
      it 'raises AuthorizationError and issues no request', :aggregate_failures do
        request = stub_request(:get, namespace_url)
        null_client = described_class.new(base_url: base_url)

        expect { null_client.namespace(uuid: uuid) }.to raise_error(described_class::AuthorizationError)
        expect(request).not_to have_been_requested
      end
    end
  end

  describe 'AR-supplied values in reports' do
    let(:uuid) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{uuid}" }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc') }
    let(:service_client) { described_class.new(base_url: base_url, service_credential: service_credential) }

    # An intermediary can echo anything here, so the header is treated like a
    # response body rather than trusted as an identifier.
    it 'redacts a credential-shaped X-Request-Id header', :aggregate_failures do
      logged = []
      allow(Gitlab::ErrorTracking).to receive(:log_exception) { |*args| logged << args }
      stub_request(:get, namespace_url).to_return(
        status: 503, body: '{}',
        headers: json_headers.merge('X-Request-Id' => 'Bearer plain-service-token'))

      expect { service_client.namespace(uuid: uuid) }.to raise_error(described_class::UnavailableError) do |error|
        expect(error.request_id).not_to include('plain-service-token')
        expect(error.request_id).to include('[REDACTED]')
      end
      expect(logged.to_s).not_to include('plain-service-token')
    end

    it 'bounds an oversized X-Request-Id header' do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_request(:get, namespace_url).to_return(
        status: 401, body: '', headers: json_headers.merge('X-Request-Id' => 'x' * 500))

      expect { service_client.namespace(uuid: uuid) }.to raise_error(described_class::AuthorizationError) do |error|
        expect(error.request_id.length).to eq(ArtifactRegistry::ErrorReporter::MAX_SNIPPET)
      end
    end

    it 'keeps the namespace uuid on a terminal failure, not only on the 404', :aggregate_failures do
      logged = []
      allow(Gitlab::ErrorTracking).to receive(:log_exception) { |*args| logged << args }
      stub_request(:get, namespace_url).to_return(status: 503, body: '{}', headers: json_headers)

      expect { service_client.namespace(uuid: uuid) }.to raise_error(described_class::UnavailableError)
      expect(logged.last.last).to include(uuid: uuid)
    end

    it 'names the AR error code on a 5xx report' do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_ar_get(status: 503, body: error_envelope(code: 'resource_exhausted').to_json)

      expect { client.repository(slug: slug, name: name) }.to raise_error(described_class::UnavailableError)
      expect(Gitlab::ErrorTracking).to have_received(:log_exception)
        .with(anything, hash_including(code: 'resource_exhausted'))
    end

    context 'when a transport failure is reported per attempt' do
      let(:logged) { [] }
      let(:reported_urls) { logged.map { |_exception, context| context[:url] } }

      before do
        allow(Gitlab::ErrorTracking).to receive(:log_exception) { |*args| logged << args }
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
        stub_request(:get, repository_url).to_raise(Faraday::ConnectionFailed)
      end

      it 'reports the failing path' do
        expect { client.repository(slug: slug, name: name) }.to raise_error(described_class::UnavailableError)
        expect(reported_urls).to include(a_string_including("/api/v1/#{slug}/repositories/#{name}"))
      end

      it 'keeps the adapter backtrace' do
        expect { client.repository(slug: slug, name: name) }.to raise_error(described_class::UnavailableError)
        expect(logged.first.first.backtrace).to be_present
      end

      context 'when the base URL ends in a slash' do
        subject(:trailing_client) do
          described_class.new(base_url: "#{base_url}/", current_user: current_user,
            token_exchange: token_exchange)
        end

        it 'does not double the separator in the reported URL' do
          expect { trailing_client.repository(slug: slug, name: name) }
            .to raise_error(described_class::UnavailableError)
          expect(reported_urls).to all(exclude('//api'))
        end
      end
    end

    it 'does not echo the configured host when the base URL cannot be parsed', :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)

      expect { described_class.new(base_url: 'https://ar-internal.example:80|80') }
        .to raise_error(described_class::ConfigurationError) do |error|
          expect(error.message).not_to include('ar-internal.example')
        end
    end
  end

  describe '#provision_namespace' do
    let(:service_token) { 'ar-service-credential-value' }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: service_token) }
    let(:namespaces_url) { "#{base_url}/api/gitlab/v1/namespaces" }

    let(:service_client) do
      described_class.new(base_url: base_url, service_credential: service_credential, token_exchange: token_exchange)
    end

    let(:provision_args) do
      {
        slug: 'my-group', platform: 'gitlab', entity_type: 'group',
        entity_id: '01920000-0000-7000-8000-000000000042',
        billing_entity_type: 'namespace', billing_entity_id: '7'
      }
    end

    let(:namespace_response) do
      {
        'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
        'slug' => 'my-group',
        'platform' => 'gitlab',
        'entity_type' => 'group',
        'entity_id' => '01920000-0000-7000-8000-000000000042',
        'status' => 'active',
        'created_at' => '2026-07-01T10:00:00Z'
      }
    end

    let(:perform) { result }
    let(:http_method) { :post }
    let(:request_url) { namespaces_url }

    subject(:result) { service_client.provision_namespace(**provision_args) }

    def stub_provision(status:, body: '', headers: json_headers)
      stub_request(:post, namespaces_url).to_return(status: status, body: body, headers: headers)
    end

    context 'when AR returns 201 with the created namespace' do
      it 'POSTs all six body fields with the service credential and returns a Namespace', :aggregate_failures do
        request = stub_request(:post, namespaces_url)
          .with(
            body: {
              slug: 'my-group', platform: 'gitlab', entity_type: 'group',
              entity_id: '01920000-0000-7000-8000-000000000042',
              billing_entity_type: 'namespace', billing_entity_id: '7'
            },
            headers: { described_class::SERVICE_TOKEN_HEADER => service_token }
          )
          .to_return(status: 201, body: namespace_response.to_json, headers: json_headers)

        expect(result).to be_a(ArtifactRegistry::Namespace)
        expect(result.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
        expect(result.status).to eq('active')
        expect(request).to have_been_requested
      end
    end

    context 'when the caller passes billing_entity_id as an integer' do
      # billing_group.id is an Integer; AR's strict decoder rejects a JSON number
      # for this string-typed field, so the client serializes it as a string.
      it 'serializes billing_entity_id as a JSON string' do
        request = stub_request(:post, namespaces_url)
          .with(body: hash_including('billing_entity_id' => '7'))
          .to_return(status: 201, body: namespace_response.to_json, headers: json_headers)

        service_client.provision_namespace(**provision_args.merge(billing_entity_id: 7))

        expect(request).to have_been_requested
      end
    end

    context 'when AR returns 200 for an exact-anchor replay' do
      it 'returns the replayed Namespace, not distinguishing 200 from 201', :aggregate_failures do
        stub_provision(status: 200, body: namespace_response.to_json)

        expect(result).to be_a(ArtifactRegistry::Namespace)
        expect(result.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      end
    end

    context 'when a required body field is blank' do
      where(:blank_field) do
        %i[slug platform entity_type entity_id billing_entity_type billing_entity_id]
      end

      with_them do
        it 'raises ArgumentError without obtaining a credential or issuing a request', :aggregate_failures do
          request = stub_request(:post, namespaces_url)

          expect { service_client.provision_namespace(**provision_args.merge(blank_field => '')) }
            .to raise_error(ArgumentError, /is required/)
          expect(service_credential).not_to have_received(:token)
          expect(request).not_to have_been_requested
        end

        it 'rejects the NOT_PROVIDED sentinel the same way', :aggregate_failures do
          request = stub_request(:post, namespaces_url)
          sentinel = described_class.const_get(:NOT_PROVIDED, false)

          expect { service_client.provision_namespace(**provision_args.merge(blank_field => sentinel)) }
            .to raise_error(ArgumentError, /is required/)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when entity_id is not a UUID' do
      # entity_id is the organization UUID; AR stores it verbatim, so the caller
      # is the only guard against a non-UUID slipping in (e.g. an integer id).
      where(:bad_entity_id) { ['42', 'not-a-uuid', '01920000-0000-7000-8000', '01920000-0000-7000-8000-0000000000zz'] }

      with_them do
        it 'raises ArgumentError without obtaining a credential or issuing a request', :aggregate_failures do
          request = stub_request(:post, namespaces_url)

          expect { service_client.provision_namespace(**provision_args.merge(entity_id: bad_entity_id)) }
            .to raise_error(ArgumentError, /entity_id must be a UUID/)
          expect(service_credential).not_to have_received(:token)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when a success response body is absent or the wrong shape' do
      it_behaves_like 'rejecting an unexpected success body', status: 201, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '[]', body_class: 'Array'

      it 'rejects a 2xx Hash body carrying no id, rather than a namespace of nils' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_provision(status: 201, body: namespace_response.except('id').to_json)

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when AR returns a 409 conflict' do
      # 409 covers both slug-taken and anchor-replay-mismatch behind the single
      # `conflict` envelope code; status, not cause, separates it from 422.
      it 'raises ApiError carrying the 409 status, conflict code, and request_id', :aggregate_failures do
        stub_provision(status: 409,
          body: error_envelope(code: 'conflict', message: 'slug already taken', request_id: 'req-409').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(409)
          expect(error.code).to eq('conflict')
          expect(error.request_id).to eq('req-409')
        end
      end

      # AR answers both causes with the same code; ops/artifact-registry#383 tracks the fix.
      it 'surfaces an anchor mismatch identically to a taken slug' do
        mismatch = 'anchor already provisioned and the request body disagrees with the stored namespace'
        stub_provision(status: 409,
          body: error_envelope(code: 'conflict', message: mismatch, request_id: 'req-409').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.code).to eq('conflict')
        end
      end
    end

    context 'when AR returns a 422 validation error' do
      it 'raises ApiError carrying the 422 status, code, and request_id', :aggregate_failures do
        stub_provision(status: 422,
          body: error_envelope(code: 'unprocessable', message: 'entity_id is invalid', request_id: 'req-422').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(422)
          expect(error.code).to eq('unprocessable')
          expect(error.request_id).to eq('req-422')
        end
      end
    end

    context 'when AR returns another mapped error status' do
      where(:status, :error_class) do
        400 | ArtifactRegistry::Client::ApiError
        413 | ArtifactRegistry::Client::ApiError
        401 | ArtifactRegistry::Client::AuthorizationError
        403 | ArtifactRegistry::Client::AuthorizationError
        429 | ArtifactRegistry::Client::UnavailableError
        500 | ArtifactRegistry::Client::UnavailableError
        503 | ArtifactRegistry::Client::UnavailableError
      end

      with_them do
        it 'follows the shared taxonomy and preserves the status', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_provision(status: status, body: error_envelope(request_id: 'req-mapped').to_json)

          expect { result }.to raise_error(error_class) do |error|
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when the service credential is absent (null default)' do
      it 'raises AuthorizationError and issues no request', :aggregate_failures do
        request = stub_request(:post, namespaces_url)
        null_client = described_class.new(base_url: base_url)

        expect { null_client.provision_namespace(**provision_args) }
          .to raise_error(described_class::AuthorizationError)
        expect(request).not_to have_been_requested
      end
    end

    context 'when asserting credential isolation' do
      it 'calls the service provider, never the per-user exchange, and sends only the service token',
        :aggregate_failures do
        request = stub_request(:post, namespaces_url)
          .with(headers: { described_class::SERVICE_TOKEN_HEADER => service_token })
          .to_return(status: 201, body: namespace_response.to_json, headers: json_headers)

        result

        expect(service_credential).to have_received(:token)
        expect(token_exchange).not_to have_received(:token_for)
        expect(request).to have_been_requested
      end
    end

    context 'when a transport failure occurs on the POST' do
      it 'does not retry and issues the POST exactly once', :aggregate_failures do
        # A private service transport that reused a status/transport retry would
        # otherwise retry the POST with the suite still green, double-applying
        # provisioning; assert exactly one request.
        stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
        stub_request(:post, namespaces_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, namespaces_url)).to have_been_made.once
      end
    end

    context 'when guarding the six-field provisioning body against every report surface' do
      # The body fields first exist in this method, so the redaction contract is
      # asserted here. entity_id's sentinel is a distinctive UUID rather than a
      # SENTINEL- string because it must satisfy the UUID guard.
      let(:sentinels) do
        {
          slug: 'SENTINEL-slug-xyz', platform: 'SENTINEL-platform-xyz',
          entity_type: 'SENTINEL-entitytype-xyz', entity_id: 'deadbeef-0000-7000-8000-00000000cafe',
          billing_entity_type: 'SENTINEL-billingtype-xyz', billing_entity_id: 'SENTINEL-billingid-xyz'
        }
      end

      # Keys any report context is allowed to carry. A leaked body field surfaces
      # either as a sentinel value or as an out-of-allowlist key, so both are
      # asserted, and a non-empty capture rules out a vacuous pass.
      report_context_keys = %i[url method correlation_id status request_id code].freeze

      define_method(:expect_no_sentinel) do |captured|
        expect(captured).not_to be_empty

        haystack = captured.map do |exception, context|
          [exception.message, exception.cause&.message, context].map(&:inspect).join(' ')
        end.join("\n")

        context_keys = captured.filter_map { |_exception, context| context }.flat_map(&:keys).uniq

        aggregate_failures 'no body field on any surface' do
          sentinels.each_value { |value| expect(haystack).not_to include(value) }
          expect(context_keys - report_context_keys).to be_empty
        end
      end

      shared_examples 'a failure outcome that leaks no body field' do
        it 'keeps every body field out of the terminal and per-attempt reports, including causes' do
          captured = []
          allow(Gitlab::ErrorTracking).to receive(:log_exception) { |exception, context| captured << [exception, context] }
          client = described_class.new(base_url: base_url, service_credential: service_credential)

          expect { client.provision_namespace(**sentinels) }.to raise_error(described_class::Error)

          # Without this the absence checks below pass vacuously for any
          # regression that stops sending the body fields at all.
          expect(a_request(:post, namespaces_url)
            .with { |req| sentinels.each_value.all? { |value| req.body.include?(value) } }).to have_been_made

          expect_no_sentinel(captured)
        end
      end

      context 'on a transport failure' do
        before do
          stub_request(:post, namespaces_url).to_raise(Faraday::ConnectionFailed.new('boom'))
        end

        it_behaves_like 'a failure outcome that leaks no body field'
      end

      context 'on a malformed success body' do
        before do
          stub_request(:post, namespaces_url)
            .to_return(status: 201, body: 'this-is-not-json', headers: json_headers)
        end

        it_behaves_like 'a failure outcome that leaks no body field'
      end

      context 'on a 429' do
        before do
          stub_request(:post, namespaces_url)
            .to_return(status: 429, body: error_envelope.to_json, headers: json_headers)
        end

        it_behaves_like 'a failure outcome that leaks no body field'
      end

      context 'on a 5xx' do
        before do
          stub_request(:post, namespaces_url)
            .to_return(status: 503, body: error_envelope.to_json, headers: json_headers)
        end

        it_behaves_like 'a failure outcome that leaks no body field'
      end
    end
  end

  describe '#disable_namespace and #enable_namespace' do
    let(:uuid) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:service_token) { 'ar-service-credential-value' }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: service_token) }

    let(:service_client) do
      described_class.new(base_url: base_url, service_credential: service_credential, token_exchange: token_exchange)
    end

    let(:namespace_response) do
      {
        'id' => uuid,
        'slug' => 'my-group',
        'platform' => 'gitlab',
        'entity_type' => 'group',
        'entity_id' => '42',
        'status' => 'active',
        'created_at' => '2026-07-01T10:00:00Z'
      }
    end

    shared_examples 'a namespace condition method' do |method:, action:|
      let(:condition_url) { "#{base_url}/api/gitlab/v1/namespaces/#{uuid}/#{action}" }

      subject(:result) { service_client.public_send(method, uuid: uuid) }

      def stub_condition(status:, body: '', headers: json_headers)
        stub_request(:post, condition_url).to_return(status: status, body: body, headers: headers)
      end

      context 'when AR returns 200 with the updated namespace' do
        it "POSTs to the #{action} path with the service credential and no body, returning a Namespace",
          :aggregate_failures do
          request = stub_request(:post, condition_url)
            .with(headers: { described_class::SERVICE_TOKEN_HEADER => service_token }) { |req| req.body.empty? }
            .to_return(status: 200, body: namespace_response.to_json, headers: json_headers)

          expect(result).to be_a(ArtifactRegistry::Namespace)
          expect(result.id).to eq(uuid)
          expect(result.status).to eq('active')
          expect(request).to have_been_requested
        end

        it 'sends no Content-Type, so AR sees no body rather than an empty JSON object', :aggregate_failures do
          stub_condition(status: 200, body: namespace_response.to_json)

          result

          expect(a_request(:post, condition_url).with { |req| !req.headers.key?('Content-Type') })
            .to have_been_made
        end

        it 'does not consult the per-user token exchange' do
          stub_condition(status: 200, body: namespace_response.to_json)

          result

          expect(token_exchange).not_to have_received(:token_for)
        end

        it 'calls the service credential provider' do
          stub_condition(status: 200, body: namespace_response.to_json)

          result

          expect(service_credential).to have_received(:token)
        end
      end

      context 'when AR returns 200 without an id' do
        it 'raises UnavailableError rather than a namespace of nils', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_condition(status: 200, body: namespace_response.except('id').to_json)

          expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
          expect(Gitlab::ErrorTracking).to have_received(:log_exception)
            .with(anything, hash_including(uuid: uuid))
        end
      end

      context 'when the transport fails' do
        it 'attributes the terminal report to the namespace uuid', :aggregate_failures do
          captured = []
          allow(Gitlab::ErrorTracking).to receive(:log_exception) { |_e, context| captured << context }
          stub_request(:post, condition_url).to_raise(Faraday::ConnectionFailed.new('boom'))

          expect { result }.to raise_error(described_class::UnavailableError)
          expect(captured).to include(hash_including(uuid: uuid))
        end
      end

      context 'when AR returns a mapped ApiError status' do
        where(:status) { [400, 404, 413] }

        with_them do
          it 'raises ApiError carrying the status' do
            stub_condition(status: status, body: error_envelope(request_id: 'req-cond').to_json)

            expect { result }.to raise_error(described_class::ApiError) do |error|
              expect(error.status).to eq(status)
              expect(error.request_id).to eq('req-cond')
            end
          end
        end
      end

      context 'when AR returns another status from the shared taxonomy' do
        where(:status, :error_class) do
          401 | ArtifactRegistry::Client::AuthorizationError
          403 | ArtifactRegistry::Client::AuthorizationError
          429 | ArtifactRegistry::Client::UnavailableError
          503 | ArtifactRegistry::Client::UnavailableError
        end

        with_them do
          it 'follows the shared mapping and preserves the status', :aggregate_failures do
            allow(Gitlab::ErrorTracking).to receive(:log_exception)
            stub_condition(status: status, body: error_envelope.to_json)

            expect { result }.to raise_error(error_class) do |error|
              expect(error.status).to eq(status)
            end
          end
        end
      end

      context 'when the service credential is absent (null default)' do
        it 'raises AuthorizationError and issues no request', :aggregate_failures do
          request = stub_request(:post, condition_url)
          null_client = described_class.new(base_url: base_url)

          expect { null_client.public_send(method, uuid: uuid) }
            .to raise_error(described_class::AuthorizationError)
          expect(request).not_to have_been_requested
        end
      end

      # Call-site encoding escapes separators; a blank or dot segment is what
      # would rewrite the request path itself.
      context 'when the uuid is blank or a dot segment' do
        where(:bad_uuid) { [nil, '', '.', '..'] }

        with_them do
          it 'raises ArgumentError before any credential is obtained or request issued', :aggregate_failures do
            request = stub_request(:post, %r{/api/gitlab/v1/namespaces/})

            expect { service_client.public_send(method, uuid: bad_uuid) }.to raise_error(ArgumentError)
            expect(request).not_to have_been_requested
            expect(service_credential).not_to have_received(:token)
          end
        end
      end

      context 'when a transport failure occurs on the POST' do
        it 'does not retry and issues the POST exactly once', :aggregate_failures do
          stub_const("#{described_class}::RETRY_OPTIONS", retry_options)
          stub_request(:post, condition_url).to_timeout

          expect { result }.to raise_error(described_class::UnavailableError)
          expect(a_request(:post, condition_url)).to have_been_made.once
        end
      end
    end

    it_behaves_like 'a namespace condition method', method: :disable_namespace, action: 'disable'
    it_behaves_like 'a namespace condition method', method: :enable_namespace, action: 'enable'

    it 'exposes no suspend/unsuspend/block/unblock methods', :aggregate_failures do
      %i[suspend_namespace unsuspend_namespace block_namespace unblock_namespace].each do |method|
        expect(service_client).not_to respond_to(method)
      end
    end
  end

  describe 'credential path isolation (one-client checkpoint)' do
    let(:uuid) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{uuid}" }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc') }
    # Permissive: would mint a token even for a nil user, so the guard (not the
    # exchange returning nil) must be the boundary.
    let(:permissive_exchange) { instance_double(ArtifactRegistry::TokenExchange, token_for: 'per-user-token') }

    it 'rejects a per-user method on a service-only instance before token_for runs', :aggregate_failures do
      request = stub_request(:get, repository_url)
      service_only = described_class.new(
        base_url: base_url, service_credential: service_credential, token_exchange: permissive_exchange
      )

      expect { service_only.repository(slug: slug, name: name) }
        .to raise_error(ArgumentError, /current_user is required/)
      expect(permissive_exchange).not_to have_received(:token_for)
      expect(request).not_to have_been_requested
    end

    it 'never consults the service credential from a per-user method', :aggregate_failures do
      stub_ar_get(status: 200, body: repository_response.to_json)

      described_class.new(base_url: base_url, current_user: current_user,
        token_exchange: token_exchange, service_credential: service_credential).repository(slug: slug, name: name)

      expect(service_credential).not_to have_received(:token)
    end

    # Paired: each example asserts both that its own path's header is present
    # and that the other path's is absent, so sending one credential's header on
    # both paths fails here rather than passing as a superset.
    it 'sends the service token in its own header and no Authorization on a service method',
      :aggregate_failures do
      stub_request(:get, namespace_url).to_return(
        status: 200, body: { 'id' => uuid }.to_json, headers: json_headers
      )

      described_class.new(base_url: base_url, service_credential: service_credential).namespace(uuid: uuid)

      expect(
        a_request(:get, namespace_url).with(headers: { described_class::SERVICE_TOKEN_HEADER => 'svc' })
      ).to have_been_made
      expect(
        a_request(:get, namespace_url).with { |req| req.headers.key?('Authorization') }
      ).not_to have_been_made
    end

    it 'sends the per-user token as a bearer and no service-token header on a per-user method',
      :aggregate_failures do
      stub_ar_get(status: 200, body: repository_response.to_json)

      described_class.new(base_url: base_url, current_user: current_user,
        token_exchange: token_exchange, service_credential: service_credential).repository(slug: slug, name: name)

      expect(a_request(:get, repository_url).with(headers: { 'Authorization' => "Bearer #{token}" }))
        .to have_been_made
      expect(
        a_request(:get, repository_url).with { |req| req.headers.key?(described_class::SERVICE_TOKEN_HEADER) }
      ).not_to have_been_made
    end

    # Redaction scrubs the credential this client transmits, so an injected
    # token (not the mounted file) is still redacted if AR echoes it back.
    it 'redacts the injected service token echoed in an error envelope', :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      injected = 'injected-service-token-abc123'
      credential = instance_double(ArtifactRegistry::ServiceCredential, token: injected)
      stub_request(:get, namespace_url)
        .to_return(status: 503, body: error_envelope(message: "rejected #{injected}").to_json, headers: json_headers)

      expect { described_class.new(base_url: base_url, service_credential: credential).namespace(uuid: uuid) }
        .to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('[REDACTED]')
          expect(error.message).not_to include(injected)
        end
    end

    # The blank guard is authed_request's, on the composed path: a credential
    # that is empty or whitespace-only must fail closed and issue no request,
    # so a future narrowing of the guard to token.nil? is caught here.
    context 'when the resolved credential is blank or whitespace-only' do
      where(:credential_value) { ['', '   '] }

      with_them do
        it 'the service path fails closed and makes no request', :aggregate_failures do
          blank_credential = instance_double(ArtifactRegistry::ServiceCredential, token: credential_value)
          client = described_class.new(base_url: base_url, service_credential: blank_credential)

          expect { client.namespace(uuid: uuid) }.to raise_error(described_class::AuthorizationError)
          expect(a_request(:get, namespace_url)).not_to have_been_made
        end

        it 'the per-user path fails closed and makes no request', :aggregate_failures do
          blank_exchange = instance_double(ArtifactRegistry::TokenExchange, token_for: credential_value)
          client = described_class.new(base_url: base_url, current_user: current_user, token_exchange: blank_exchange)

          expect { client.repository(slug: slug, name: name) }.to raise_error(described_class::AuthorizationError)
          expect(a_request(:get, repository_url)).not_to have_been_made
        end
      end
    end

    # A credential that raises AuthorizationError (unreadable or charset-invalid
    # mount) must surface as a Client::Error the caller can rescue, and must not
    # crash the reporter's fallback branch on the way out.
    context 'when the resolved credential raises AuthorizationError' do
      let(:raising_credential) do
        instance_double(ArtifactRegistry::ServiceCredential).tap do |cred|
          allow(cred).to receive(:token).and_raise(described_class::AuthorizationError, 'service token unreadable')
        end
      end

      it 'surfaces AuthorizationError as a Client::Error and makes no request', :aggregate_failures do
        client = described_class.new(base_url: base_url, service_credential: raising_credential)

        expect { client.namespace(uuid: uuid) }.to raise_error(described_class::Error)
        expect(a_request(:get, namespace_url)).not_to have_been_made
      end

      it 'builds a usable reporter through the fallback rather than crashing' do
        client = described_class.new(base_url: base_url, service_credential: raising_credential)

        expect(client.send(:reporter)).to be_a(ArtifactRegistry::ErrorReporter)
      end
    end
  end

  describe 'terminal cause attachment' do
    let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/uuid-1" }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc') }

    it 'raises UnavailableError whose cause is the original transport failure', :aggregate_failures do
      client = described_class.new(base_url: base_url, service_credential: service_credential)
      stub_request(:get, namespace_url).to_raise(Faraday::ConnectionFailed)

      expect { client.namespace(uuid: 'uuid-1') }.to raise_error(described_class::UnavailableError) do |error|
        expect(error.cause).to be_a(Faraday::ConnectionFailed)
      end
    end
  end

  describe 'origin validation' do
    it 'accepts http outside production, matching what the frontend helper renders', :aggregate_failures do
      ['http://localhost:8080', 'http://gdk.test:8080',
        'http://artifact-registry.gitlab.svc.cluster.local:8080'].each do |url|
        expect { described_class.new(base_url: url) }.not_to raise_error
      end
    end

    context 'in production' do
      let(:plaintext_url) { 'http://ar.test' }
      let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc') }

      before do
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'still constructs with a plaintext base URL, since the guard is at request time' do
        expect { described_class.new(base_url: plaintext_url, current_user: current_user) }
          .not_to raise_error
      end

      it 'refuses http on the per-user path before the token is minted', :aggregate_failures do
        request = stub_request(:post, %r{/connection_test})
        client = described_class.new(
          base_url: plaintext_url, current_user: current_user, token_exchange: token_exchange)

        expect { client.test_namespace_upstream_connection(slug: 'grp', format: 'maven', url: 'https://up.test') }
          .to raise_error(described_class::ConfigurationError, /HTTPS in production/)
        expect(request).not_to have_been_requested
        expect(token_exchange).not_to have_received(:token_for)
      end

      it 'refuses http on the service path before the token is read', :aggregate_failures do
        request = stub_request(:get, %r{/api/gitlab/v1/namespaces})
        client = described_class.new(base_url: plaintext_url, service_credential: service_credential)

        expect { client.namespace(uuid: 'a1b2c3d4-0000-0000-0000-000000000000') }
          .to raise_error(described_class::ConfigurationError, /HTTPS in production/)
        expect(request).not_to have_been_requested
        expect(service_credential).not_to have_received(:token)
      end
    end

    it 'logs the configured host when the base URL cannot be parsed', :aggregate_failures do
      logged = []
      allow(Gitlab::ErrorTracking).to receive(:log_exception) { |_e, context| logged << context }

      expect { described_class.new(base_url: 'https://ar-internal.example:80|80') }
        .to raise_error(described_class::ConfigurationError) do |error|
          expect(error.message).not_to include('ar-internal.example')
        end
      expect(logged.first).to include(url: 'https://ar-internal.example:80|80')
    end

    # Each method builds its own absolute path, so a base path would be duplicated.
    it 'rejects a path-bearing base_url', :aggregate_failures do
      ['https://ar.test/api/v1', 'https://ar.test/nested/path'].each do |url|
        expect { described_class.new(base_url: url) }
          .to raise_error(described_class::ConfigurationError, /must not carry a path/)
      end

      expect { described_class.new(base_url: 'https://ar.test/') }.not_to raise_error
    end

    # The base URL is logged verbatim in error contexts, so a credential-bearing
    # URL must not construct at all.
    it 'rejects userinfo, query, and fragment', :aggregate_failures do
      ['https://user:secret@ar.test', 'https://ar.test?token=abc', 'https://ar.test#frag'].each do |url|
        expect { described_class.new(base_url: url) }.to raise_error(described_class::ConfigurationError)
      end
    end

    it 'raises ConfigurationError, not a raw parser error, on a malformed URL', :aggregate_failures do
      ['http://[::1%25eth0]:8080', 'http://exa mple.test', ':::'].each do |url|
        expect { described_class.new(base_url: url) }.to raise_error(described_class::ConfigurationError)
      end
    end

    it 'does not mint or send a credential when the base URL is invalid', :aggregate_failures do
      expect { described_class.new(base_url: 'https://u:p@ar.test', token_exchange: token_exchange) }
        .to raise_error(described_class::ConfigurationError)
      expect(token_exchange).not_to have_received(:token_for)
    end
  end

  describe 'correlation id resolution' do
    let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/uuid-1" }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc') }

    it 'resolves the current correlation id per request, not at construction', :aggregate_failures do
      client = described_class.new(base_url: base_url, service_credential: service_credential)

      Labkit::Correlation::CorrelationId.use_id('corr-1') do
        request = stub_request(:get, namespace_url)
          .with(headers: { 'X-Request-Id' => 'corr-1' })
          .to_return(status: 200, body: { id: 'uuid-1' }.to_json, headers: json_headers)
        client.namespace(uuid: 'uuid-1')
        expect(request).to have_been_requested
      end
    end
  end

  describe '#verify_repositories' do
    subject(:result) do
      service_client.verify_repositories(namespace_id: namespace_id, repository_ids: repository_ids)
    end

    let(:service_token) { 'ar-service-credential-value' }
    let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: service_token) }
    let(:service_client) { described_class.new(base_url: base_url, service_credential: service_credential) }
    let(:namespace_id) { Gitlab::Utils.uuid_v7 }
    let(:repository_ids) { [Gitlab::Utils.uuid_v7, Gitlab::Utils.uuid_v7] }
    let(:verifications_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_id}/repositories/verifications" }

    context 'when every id belongs (204)' do
      it 'posts the batch with the service credential and returns an empty array', :aggregate_failures do
        request = stub_request(:post, verifications_url)
          .with(
            body: { repository_ids: repository_ids }.to_json,
            headers: { described_class::SERVICE_TOKEN_HEADER => service_token }
          )
          .to_return(status: 204)

        expect(result).to eq([])
        expect(request).to have_been_requested
      end
    end

    # namespace_id is spent on the AR URL and never written to IAM, so it is
    # held to what AR accepts rather than the UUIDv7 rule IAM imposes.
    context 'when AR answers a 2xx that is not 204' do
      it 'refuses rather than reading it as an all-belong verdict' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:post, verifications_url)
          .to_return(status: 200, body: {}.to_json, headers: json_headers)

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected status/)
      end
    end

    context 'when the namespace id is a canonical UUID of another version' do
      let(:namespace_id) { SecureRandom.uuid }

      it 'issues the request rather than rejecting the id', :aggregate_failures do
        request = stub_request(:post, verifications_url).to_return(status: 204)

        expect(result).to eq([])
        expect(request).to have_been_requested
      end
    end

    context 'when some ids fail verification (422)' do
      it 'returns the failing ids from error.details' do
        body = {
          error: {
            code: 'unprocessable_entity',
            message: 'one or more repository ids do not identify a repository in this namespace',
            details: { repository_ids: [repository_ids.first] }
          }
        }
        stub_request(:post, verifications_url).to_return(status: 422, body: body.to_json, headers: json_headers)

        expect(result).to eq([repository_ids.first])
      end
    end

    context 'when a 422 names ids the caller never submitted' do
      it 'drops the extras and returns only the submitted ids', :aggregate_failures do
        stray = Gitlab::Utils.uuid_v7
        body = {
          error: {
            code: 'unprocessable_entity',
            message: 'one or more repository ids do not identify a repository in this namespace',
            details: { repository_ids: [repository_ids.first, stray] }
          }
        }
        stub_request(:post, verifications_url).to_return(status: 422, body: body.to_json, headers: json_headers)

        expect(result).to eq([repository_ids.first])
        expect(result).not_to include(stray)
      end

      it 'raises UnavailableError when every named id is a stray' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        body = {
          error: {
            code: 'unprocessable_entity',
            message: 'one or more repository ids do not identify a repository in this namespace',
            details: { repository_ids: [Gitlab::Utils.uuid_v7] }
          }
        }
        stub_request(:post, verifications_url).to_return(status: 422, body: body.to_json, headers: json_headers)

        expect { result }.to raise_error(described_class::UnavailableError, /unreadable verification failure/)
      end
    end

    context 'when a 422 carries no failing ids' do
      it 'raises UnavailableError rather than inventing a verdict' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:post, verifications_url)
          .to_return(status: 422, body: error_envelope(code: 'unprocessable_entity').to_json, headers: json_headers)

        expect { result }.to raise_error(described_class::UnavailableError, /unreadable verification failure/)
      end
    end

    context 'when the namespace is unknown (404)' do
      it 'raises ApiError' do
        stub_request(:post, verifications_url)
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect { result }.to raise_error(described_class::ApiError) { |e| expect(e.status).to eq(404) }
      end
    end

    context 'when AR is failing (500)' do
      it 'raises UnavailableError and reports the namespace under an allowlisted key', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:post, verifications_url)
          .to_return(status: 500, body: error_envelope.to_json, headers: json_headers)

        expect { result }.to raise_error(described_class::UnavailableError)
        # ErrorReporter slices context to ALLOWED_CONTEXT_KEYS, so a key outside
        # that set names the namespace nowhere in the report.
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::UnavailableError), hash_including(uuid: namespace_id)
        )
      end
    end

    context 'when no functional service credential is wired' do
      let(:service_credential) { ArtifactRegistry::ServiceCredential.new }

      it 'raises AuthorizationError without issuing a request', :aggregate_failures do
        request = stub_request(:post, verifications_url).to_return(status: 204)

        expect { result }.to raise_error(described_class::AuthorizationError)
        expect(request).not_to have_been_requested
      end
    end

    context 'with invalid caller input' do
      it 'rejects a non-canonical namespace id without a request' do
        expect do
          service_client.verify_repositories(namespace_id: namespace_id.upcase, repository_ids: repository_ids)
        end.to raise_error(ArgumentError, /namespace_id/)
      end

      it 'rejects an empty batch without a request' do
        expect do
          service_client.verify_repositories(namespace_id: namespace_id, repository_ids: [])
        end.to raise_error(ArgumentError, /between 1 and/)
      end

      it 'rejects an oversized batch without a request' do
        ids = Array.new(described_class::MAX_VERIFICATION_BATCH + 1) { Gitlab::Utils.uuid_v7 }

        expect do
          service_client.verify_repositories(namespace_id: namespace_id, repository_ids: ids)
        end.to raise_error(ArgumentError, /between 1 and/)
      end

      it 'rejects a non-canonical repository id without a request' do
        expect do
          service_client.verify_repositories(namespace_id: namespace_id, repository_ids: [repository_ids.first.upcase])
        end.to raise_error(ArgumentError, /repository_ids/)
      end
    end
  end

  def stub_ar_get(status:, body: '')
    stub_request(:get, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def stub_ar_patch(status:, body: '')
    stub_request(:patch, repository_url).to_return(status: status, body: body, headers: json_headers)
  end

  def stub_ar_delete(status:, body: '')
    stub_request(:delete, repository_url)
      .with(query: { destructive: 'true' })
      .to_return(status: status, body: body, headers: json_headers)
  end

  def stub_ar_list(body:, headers: json_headers)
    stub_request(:get, request_url).to_return(status: 200, body: body, headers: headers)
  end

  def error_envelope(code: 'error_code', message: 'something went wrong', request_id: 'req-envelope-id')
    { error: { code: code, message: message, request_id: request_id } }
  end

  def repository_permissions
    ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true).merge('delete_repository' => false)
  end

  def namespace_permissions
    ArtifactRegistry::Permissions::Verdicts::NAMESPACE_ACTIONS.index_with(true).merge('delete_repository' => false)
  end
end
