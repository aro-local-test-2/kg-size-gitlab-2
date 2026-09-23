# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Openai::ServiceAccountKey,
  feature_category: :secret_detection do
  let(:valid_token) { "sk-svcacct-#{'a' * 40}" }

  it_behaves_like 'an OpenAI token verifier', path: '/v1/models'
end
