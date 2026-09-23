# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Openai::AdminKey,
  feature_category: :secret_detection do
  let(:valid_token) { "sk-admin-#{'a' * 124}" }

  it_behaves_like 'an OpenAI token verifier', path: '/v1/organization/admin_api_keys'
end
