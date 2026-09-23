# frozen_string_literal: true

# The Stripe status mapping, which lives on Stripe::Base and is therefore identical for
# every Stripe verifier. Each including spec supplies `valid_token`, so a type's spec only
# states what makes it different.
RSpec.shared_examples 'a Stripe token verifier' do
  let(:client) { described_class.new }
  let(:response) { instance_double(HTTParty::Response) }
  let(:endpoint) { Security::SecretDetection::PartnerTokens::Stripe::Base::API_ENDPOINT }

  it_behaves_like 'a partner token client', http_method: :get

  describe '#verify_token' do
    using RSpec::Parameterized::TableSyntax

    context 'with vendor status mapping' do
      where(:status_code, :predicate) do
        200 | :active?
        401 | :inactive?
        403 | :active?
        404 | :unknown?
      end

      with_them do
        before do
          allow(response).to receive_messages(code: status_code.to_s, body: '{}')
          allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
        end

        it 'returns the appropriate status' do
          expect(client.verify_token(valid_token).public_send(predicate)).to be(true)
        end
      end
    end

    context 'with rate limiting and service errors' do
      where(:status_code, :error_class) do
        429 | described_class::RateLimitError
        500 | described_class::NetworkError
        502 | described_class::NetworkError
        503 | described_class::NetworkError
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

    it 'sends the key as the HTTP Basic username to the balance endpoint' do
      allow(response).to receive_messages(code: '200', body: '{}')
      expected = "Basic #{Base64.strict_encode64("#{valid_token}:")}"
      expect(Integrations::Clients::HTTP).to receive(:get)
        .with(endpoint, headers: hash_including('Authorization' => expected))
        .and_return(response)

      client.verify_token(valid_token)
    end

    it 'reports the vendor as the partner, not the token type' do
      allow(response).to receive_messages(code: '200', body: '{}')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).metadata[:partner]).to eq('STRIPE')
    end
  end
end
