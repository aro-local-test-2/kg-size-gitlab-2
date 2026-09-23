# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::PostmanClient, feature_category: :secret_detection do
  using RSpec::Parameterized::TableSyntax

  let(:client) { described_class.new }
  let(:response) { instance_double(Net::HTTPResponse) }
  let(:valid_api_key) { "PMAK-#{SecureRandom.hex(12)}-#{SecureRandom.hex(17)}" }

  describe '#verify_token' do
    context 'with valid token format' do
      before do
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      context 'with different response scenarios' do
        let(:auth_error_body) do
          '{"error":{"message":"Invalid API Key. Every request requires a valid API Key to be sent.",' \
            '"name":"AuthenticationError"}}'
        end

        where(:code, :body, :expected_status_check) do
          '200' | '{}'                                  | :active?
          '401' | ref(:auth_error_body)                 | :inactive?
          '401' | '{"error":{"name":"BlockedError"}}'   | :unknown?
          '401' | '{"error":"Unauthorized"}'            | :unknown?
          '401' | '["AuthenticationError"]'             | :unknown?
          '401' | '<html>Access denied</html>'          | :unknown?
          '404' | '{}'                                  | :unknown?
          '200' | ''                                    | :active?
        end

        with_them do
          before do
            allow(response).to receive_messages(code: code, body: body)
          end

          it 'handles response correctly' do
            result = client.verify_token(valid_api_key)
            expect(result.send(expected_status_check)).to be true
          end
        end
      end

      context 'when a 401 body is not the vendor invalid-key verdict' do
        before do
          allow(response).to receive_messages(code: '401', body: '{"error":{"name":"BlockedError"}}')
        end

        it 'never reports inactive and warns for diagnosability' do
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(partner: 'postman'))

          result = client.verify_token(valid_api_key)

          expect(result.inactive?).to be false
          expect(result.unknown?).to be true
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

          it 'raises appropriate error' do
            expect { client.verify_token(valid_api_key) }
              .to raise_error(error_class, error_pattern)
          end
        end
      end

      context 'with network errors' do
        it 'raises NetworkError on timeout' do
          allow(Integrations::Clients::HTTP).to receive(:get)
            .and_raise(Net::ReadTimeout.new('timeout'))

          expect { client.verify_token(valid_api_key) }
            .to raise_error(described_class::NetworkError)
        end

        it 'raises NetworkError on connection refused' do
          allow(Integrations::Clients::HTTP).to receive(:get)
            .and_raise(Errno::ECONNREFUSED.new('connection refused'))

          expect { client.verify_token(valid_api_key) }
            .to raise_error(described_class::NetworkError)
        end

        it 'raises NetworkError on standard error' do
          allow(Integrations::Clients::HTTP).to receive(:get)
            .and_raise(StandardError.new('unexpected'))

          expect { client.verify_token(valid_api_key) }
            .to raise_error(described_class::NetworkError, /Unexpected error/)
        end
      end

      context 'with response error' do
        before do
          allow(response).to receive_messages(code: '200', body: '{}')
          allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
          allow(client).to receive(:analyze_postman_response)
            .and_raise(described_class::ResponseError.new('Invalid response format'))
        end

        it 'returns unknown status' do
          result = client.verify_token(valid_api_key)
          expect(result.unknown?).to be true
          expect(result.metadata[:partner]).to eq('POSTMAN')
          expect(result.metadata[:verified_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
        end
      end

      it 'sends token in X-API-Key header' do
        allow(response).to receive_messages(code: '200', body: '{}')

        client.verify_token(valid_api_key)

        expect(Integrations::Clients::HTTP).to have_received(:get)
          .with(
            described_class::API_ENDPOINT,
            headers: hash_including(
              'X-API-Key' => valid_api_key,
              'Accept' => 'application/json'
            )
          )
      end

      it 'includes partner name in metadata' do
        allow(response).to receive_messages(code: '200', body: '{}')

        result = client.verify_token(valid_api_key)

        expect(result.metadata[:partner]).to eq('POSTMAN')
        expect(result.metadata[:verified_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      end
    end

    context 'with rate limit considerations' do
      before do
        allow(response).to receive(:code).and_return('429')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'raises RateLimitError for 429 responses' do
        expect { client.verify_token(valid_api_key) }
          .to raise_error(described_class::RateLimitError, /Postman API rate limited/)
      end

      it 'includes response code in rate limit error message' do
        expect { client.verify_token(valid_api_key) }
          .to raise_error(described_class::RateLimitError, /429/)
      end
    end

    context 'with unexpected response codes' do
      before do
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        allow(response).to receive_messages(code: code, body: '{}')
      end

      where(:code) do
        %w[400 403 405 422 301 302]
      end

      with_them do
        it 'returns unknown status for unexpected response codes' do
          result = client.verify_token(valid_api_key)
          expect(result.unknown?).to be true
        end
      end
    end

    context 'with retryable errors' do
      it 'propagates RateLimitError for worker retry handling' do
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        allow(response).to receive(:code).and_return('429')

        expect { client.verify_token(valid_api_key) }
          .to raise_error(described_class::RateLimitError)
      end

      it 'propagates NetworkError for worker retry handling' do
        allow(Integrations::Clients::HTTP).to receive(:get)
          .and_raise(Net::ReadTimeout.new('timeout'))

        expect { client.verify_token(valid_api_key) }
          .to raise_error(described_class::NetworkError)
      end
    end
  end
end
