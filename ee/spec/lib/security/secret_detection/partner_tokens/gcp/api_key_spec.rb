# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Gcp::ApiKey, feature_category: :secret_detection do
  using RSpec::Parameterized::TableSyntax

  let(:client) { described_class.new }
  let(:valid_token) { "AIza#{'a' * 35}" }
  let(:response) { instance_double(Net::HTTPResponse) }

  let(:invalid_key_body) do
    {
      error: {
        code: 400,
        message: 'API key not valid. Please pass a valid API key.',
        status: 'INVALID_ARGUMENT',
        details: [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'API_KEY_INVALID' }]
      }
    }.to_json
  end

  let(:restricted_key_body) do
    {
      error: {
        code: 403,
        message: 'Requests to this API are blocked.',
        status: 'PERMISSION_DENIED',
        details: [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'API_KEY_SERVICE_BLOCKED' }]
      }
    }.to_json
  end

  let(:keyless_forbidden_body) do
    {
      error: {
        code: 403,
        message: "Method doesn't allow unregistered callers",
        status: 'PERMISSION_DENIED'
      }
    }.to_json
  end

  it_behaves_like 'a partner token client', http_method: :get

  describe '#verify_token' do
    before do
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
    end

    context 'with different response scenarios' do
      where(:code, :body, :expected_status_check) do
        '200' | '{"kind": "discovery#directoryList", "items": []}' | :active?
        '400' | ref(:invalid_key_body) | :inactive?
        '400' | '{"error": {"code": 400, "status": "INVALID_ARGUMENT", "details": []}}' | :unknown?
        '400' | '{"error": {"code": 400}}' | :unknown?
        '403' | ref(:restricted_key_body) | :active?
        '403' | ref(:keyless_forbidden_body) | :unknown?
        '403' | '{"error": {"details": [{"reason": "CONSUMER_SUSPENDED"}]}}' | :unknown?
        '404' | 'Not Found' | :unknown?
      end

      with_them do
        before do
          allow(response).to receive_messages(code: code, body: body)
        end

        it 'maps the response to the expected status' do
          result = client.verify_token(valid_token)
          expect(result.send(expected_status_check)).to be true
        end
      end
    end

    context 'when the 400 body is not JSON' do
      before do
        allow(response).to receive_messages(code: '400', body: '<html>blocked</html>')
      end

      it 'returns unknown rather than inactive' do
        result = client.verify_token(valid_token)

        expect(result.unknown?).to be true
        expect(result.inactive?).to be false
      end
    end

    context 'with rate limiting and service errors' do
      where(:code, :error_class, :error_pattern) do
        '429' | described_class::RateLimitError | /rate limited/
        '500' | described_class::NetworkError   | /service error/
        '502' | described_class::NetworkError   | /service error/
        '503' | described_class::NetworkError   | /service error/
        '504' | described_class::NetworkError   | /service error/
      end

      with_them do
        before do
          allow(response).to receive(:code).and_return(code)
        end

        it 'raises the appropriate error' do
          expect { client.verify_token(valid_token) }
            .to raise_error(error_class, error_pattern)
        end
      end
    end

    it 'sends the key in the X-Goog-Api-Key header, not the URL' do
      allow(response).to receive_messages(code: '200', body: '{}')

      client.verify_token(valid_token)

      expect(Integrations::Clients::HTTP).to have_received(:get).with(
        described_class::API_ENDPOINT,
        hash_including(headers: hash_including('X-Goog-Api-Key' => valid_token))
      )
      expect(described_class::API_ENDPOINT).not_to include(valid_token)
    end

    it 'reports gcp as the partner in metadata' do
      allow(response).to receive_messages(code: '200', body: '{}')

      result = client.verify_token(valid_token)

      expect(result.metadata[:partner]).to eq('GCP')
    end
  end
end
