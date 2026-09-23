# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Gcp::OauthClientSecret, feature_category: :secret_detection do
  let(:client) { described_class.new }

  describe '#verify_token' do
    it 'returns unknown without calling any vendor endpoint' do
      allow(Integrations::Clients::HTTP).to receive(:get)
      allow(Integrations::Clients::HTTP).to receive(:post)

      result = client.verify_token("GOCSPX-#{'a' * 28}")

      expect(result.unknown?).to be true
      expect(Integrations::Clients::HTTP).not_to have_received(:get)
      expect(Integrations::Clients::HTTP).not_to have_received(:post)
    end
  end
end
