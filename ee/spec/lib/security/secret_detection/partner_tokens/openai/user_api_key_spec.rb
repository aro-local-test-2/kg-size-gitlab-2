# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Openai::UserApiKey,
  feature_category: :secret_detection do
  let(:valid_token) { "sk-#{'a' * 48}" }

  it_behaves_like 'an OpenAI token verifier', path: '/v1/models'
end
