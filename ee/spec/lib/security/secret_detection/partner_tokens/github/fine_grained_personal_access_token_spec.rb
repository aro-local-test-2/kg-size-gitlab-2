# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Github::FineGrainedPersonalAccessToken,
  feature_category: :secret_detection do
  let(:valid_token) { "github_pat_#{'a' * 22}_#{'a' * 59}" }

  it_behaves_like 'a GitHub token verifier', path: '/user'
end
