# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Stripe::LiveShortSecretKey,
  feature_category: :secret_detection do
  let(:valid_token) { "sk_live_#{'a' * 24}" }

  it_behaves_like 'a Stripe token verifier'
end
