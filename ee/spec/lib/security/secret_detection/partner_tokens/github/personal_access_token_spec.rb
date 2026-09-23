# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Github::PersonalAccessToken,
  feature_category: :secret_detection do
  let(:valid_token) { "ghp_#{'a' * 36}" }

  it_behaves_like 'a GitHub token verifier', path: '/user'
end
