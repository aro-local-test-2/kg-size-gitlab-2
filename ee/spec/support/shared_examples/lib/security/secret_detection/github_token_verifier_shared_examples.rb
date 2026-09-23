# frozen_string_literal: true

# The GitHub status mapping, which lives on Github::Base and is therefore identical for
# every GitHub verifier. Each including spec supplies `valid_token` and its own endpoint
# path, so a type's spec only states what makes it different.
RSpec.shared_examples 'a GitHub token verifier' do |path:|
  let(:client) { described_class.new }
  let(:response) { instance_double(HTTParty::Response) }
  let(:endpoint) { "#{Security::SecretDetection::PartnerTokens::Github::Base::API_BASE_URL}#{path}" }

  it_behaves_like 'a partner token client', http_method: :get

  describe '#verify_token' do
    using RSpec::Parameterized::TableSyntax

    context 'with vendor status mapping' do
      where(:status_code, :predicate) do
        200 | :active?
        401 | :inactive?
        404 | :unknown?
      end

      with_them do
        before do
          allow(response).to receive_messages(code: status_code.to_s, headers: {})
          allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        end

        it 'returns the appropriate status' do
          expect(client.verify_token(valid_token).public_send(predicate)).to be(true)
        end
      end
    end

    context 'with retryable responses' do
      where(:status_code, :headers, :error_class) do
        403 | { 'x-ratelimit-remaining' => '0' } | described_class::RateLimitError
        403 | { 'retry-after' => '60' }          | described_class::RateLimitError
        429 | {}                                 | described_class::RateLimitError
        500 | {}                                 | described_class::NetworkError
        502 | {}                                 | described_class::NetworkError
        503 | {}                                 | described_class::NetworkError
        504 | {}                                 | described_class::NetworkError
      end

      with_them do
        before do
          allow(response).to receive_messages(code: status_code.to_s, headers: headers)
          allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        end

        it 'raises the appropriate error' do
          expect { client.verify_token(valid_token) }.to raise_error(error_class, /#{status_code}/)
        end
      end
    end

    context 'with a forbidden response that is not throttling' do
      before do
        allow(response).to receive_messages(code: '403', headers: {}, body: '{"message":"Forbidden"}')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'returns unknown rather than inactive' do
        result = client.verify_token(valid_token)

        expect(result.unknown?).to be(true)
      end
    end

    context 'with a secondary rate limit carrying neither throttle header' do
      before do
        allow(response).to receive_messages(
          code: '403',
          headers: {},
          body: '{"message":"You have exceeded a secondary rate limit."}'
        )
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      end

      it 'raises the rate limit error rather than falling through to unknown' do
        expect { client.verify_token(valid_token) }
          .to raise_error(described_class::RateLimitError, /403/)
      end
    end

    it 'sends the token as a Bearer credential to its own endpoint' do
      allow(response).to receive_messages(code: '200', headers: {})
      expect(Integrations::Clients::HTTP).to receive(:get)
        .with(endpoint, headers: hash_including(
          'Authorization' => "Bearer #{valid_token}",
          'Accept' => 'application/vnd.github+json',
          'X-GitHub-Api-Version' => '2022-11-28'
        ))
        .and_return(response)

      client.verify_token(valid_token)
    end

    it 'reports the vendor as the partner, not the token type' do
      allow(response).to receive_messages(code: '200', headers: {})
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).metadata[:partner]).to eq('GITHUB')
    end
  end
end
