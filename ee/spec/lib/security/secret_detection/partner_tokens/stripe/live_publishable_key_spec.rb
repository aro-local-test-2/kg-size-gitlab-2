# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Stripe::LivePublishableKey,
  feature_category: :secret_detection do
  let(:valid_token) { "pk_live_#{'a' * 99}" }

  it_behaves_like 'a Stripe token verifier'
end
