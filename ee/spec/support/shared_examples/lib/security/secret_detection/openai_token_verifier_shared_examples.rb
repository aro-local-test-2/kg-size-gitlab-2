# frozen_string_literal: true

# The OpenAI status mapping, which lives on Openai::Base and is therefore identical for every
# OpenAI verifier. Each including spec supplies `valid_token` and its own endpoint path, so a
# type's spec only states what makes it different.
RSpec.shared_examples 'an OpenAI token verifier' do |path:|
  let(:client) { described_class.new }
  let(:response) { instance_double(Net::HTTPResponse) }
  let(:endpoint) { "#{Security::SecretDetection::PartnerTokens::Openai::Base::API_BASE_URL}#{path}" }

  it_behaves_like 'a partner token client', http_method: :get

  describe '#verify_token' do
    using RSpec::Parameterized::TableSyntax

    context 'with vendor status mapping' do
      # OpenAI documents four causes of 401 and only invalid_api_key means the key is dead.
      # The others - an organization mismatch, an account in no organization, and an IP
      # outside the allowlist - describe a live key this request cannot use.
      #
      # A 401 carrying `error` as a plain string has never been observed, but the 403s do use
      # that shape, so it must degrade to unknown rather than raise.
      where(:status_code, :body, :predicate) do
        200 | '{}'                                                                  | :active?
        401 | '{"error":{"code":"invalid_api_key"}}'                                | :inactive?
        401 | '{"error":{"message":"Your account is not part of an organization"}}' | :unknown?
        401 | '{"error":"Incorrect API key provided"}'                              | :unknown?
        403 | '{"error":"Country, region, or territory not supported"}'             | :unknown?
        404 | '{}'                                                                  | :unknown?
      end

      with_them do
        before do
          allow(response).to receive_messages(code: status_code.to_s, body: body)
          allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        end

        it 'classifies the token' do
          expect(client.verify_token(valid_token).public_send(predicate)).to be(true)
        end
      end
    end

    context 'with a 403 that mentions permissions but names no scope' do
      before do
        allow(response).to receive_messages(
          code: '403',
          body: '{"error":"This operation requires elevated permissions."}'
        )
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      # Both phrases are required, so a partial match must not be read as a live key.
      it 'returns unknown' do
        result = client.verify_token(valid_token)

        expect(result.unknown?).to be(true)
      end
    end

    context 'with a scope refusal' do
      before do
        allow(response).to receive_messages(
          code: '403',
          body: '{"error":"You have insufficient permissions for this operation. ' \
            'Missing scopes: api.model.read."}'
        )
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      # OpenAI returns this only after resolving the key, so the key is live.
      it 'returns active, never inactive' do
        result = client.verify_token(valid_token)

        expect(result.active?).to be(true)
      end
    end

    context 'with rate limiting and service errors' do
      where(:status_code, :error_class) do
        429 | described_class::RateLimitError
        500 | described_class::NetworkError
        504 | described_class::NetworkError
      end

      with_them do
        before do
          allow(response).to receive_messages(code: status_code.to_s, body: '')
          allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        end

        it 'raises the appropriate error' do
          expect { client.verify_token(valid_token) }.to raise_error(error_class, /#{status_code}/)
        end
      end
    end

    it 'sends the key as a Bearer credential to its own endpoint' do
      allow(response).to receive_messages(code: '200', body: '{}')
      expect(Integrations::Clients::HTTP).to receive(:get)
        .with(endpoint, headers: hash_including('Authorization' => "Bearer #{valid_token}"))
        .and_return(response)

      client.verify_token(valid_token)
    end

    it 'reports the vendor as the partner, not the token type' do
      allow(response).to receive_messages(code: '200', body: '{}')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).metadata[:partner]).to eq('OPENAI')
    end
  end
end
