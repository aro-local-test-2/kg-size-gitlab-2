# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Stripe::TestRestrictedKey,
  feature_category: :secret_detection do
  let(:valid_token) { "rk_test_#{'a' * 99}" }

  it_behaves_like 'a Stripe token verifier'
end
