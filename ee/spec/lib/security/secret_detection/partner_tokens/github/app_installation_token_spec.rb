# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Github::AppInstallationToken,
  feature_category: :secret_detection do
  let(:valid_token) { "v1.#{'a' * 40}" }

  it_behaves_like 'a GitHub token verifier', path: '/installation/repositories'
end
