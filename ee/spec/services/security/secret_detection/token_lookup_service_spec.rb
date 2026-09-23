# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::TokenLookupService, feature_category: :secret_detection do
  let(:service) { described_class.new }

  describe '#find' do
    context 'with multiple personal access tokens and PAT routable tokens' do
      let_it_be(:raw_token_values) do
        Array.new(4) { |i| format('glpat-%020d', i) } +
          Array.new(4) { |i| format('glpat-%027d', i) }
      end

      let_it_be(:personal_access_tokens) do
        create_list(:personal_access_token, raw_token_values.size).tap do |tokens|
          raw_token_values.each_with_index do |value, index|
            tokens[index].update_column(:token_digest, Gitlab::CryptoHelper.sha256(value))
          end
        end
      end

      it 'finds the tokens' do
        results = service.find('gitlab_personal_access_token', raw_token_values)
        expect(results.size).to eq(raw_token_values.size)

        raw_token_values.each_with_index do |token_value, i|
          found_token = results[token_value]
          expect(found_token.token_digest).to eq(personal_access_tokens[i].token_digest)
        end
      end
    end

    context 'with multiple deploy tokens' do
      let(:deploy_tokens) { create_list(:deploy_token, 4) }
      let(:raw_token_values) { deploy_tokens.map(&:token) }

      it 'finds multiple tokens by their values and type' do
        results = service.find('gitlab_deploy_token', raw_token_values)
        expect(results).to match(raw_token_values.zip(deploy_tokens).to_h)
      end
    end

    context 'with multiple runner auth tokens' do
      let_it_be(:runners) { create_list(:ci_runner, 4) }
      let(:raw_token_values) { runners.map(&:token) }

      it 'finds multiple tokens by their values and type' do
        results = service.find('gitlab_runner_auth_token', raw_token_values)
        expect(results).to match(raw_token_values.zip(runners).to_h)
      end
    end

    context 'with multiple runner auth routable tokens' do
      let_it_be(:project) { create(:project) }
      let_it_be(:routable_runners) { create_list(:ci_runner, 4, :project, projects: [project]) }
      let(:raw_token_values) { routable_runners.map(&:token) }

      it 'finds multiple tokens by their values and type' do
        results = service.find('gitlab_runner_auth_token_routable', raw_token_values)
        expect(results).to match(raw_token_values.zip(routable_runners).to_h)
      end
    end

    context 'when searching for existing and non-existing tokens' do
      let(:existing_token_values) { Array.new(3) { |i| format('glpat-%020d', i) } }
      let(:non_existing_token_values) { Array.new(2) { |i| format('glpat-nonexistent%015d', i) } }
      let(:all_token_values) { existing_token_values + non_existing_token_values }
      let(:existing_tokens) { create_list(:personal_access_token, existing_token_values.size) }

      before do
        existing_token_values.each_with_index do |value, index|
          existing_tokens[index].update_column(:token_digest, Gitlab::CryptoHelper.sha256(value))
        end
      end

      it 'finds only the existing tokens' do
        result = service.find('gitlab_personal_access_token', all_token_values)

        expect(result.size).to eq(existing_token_values.size)
        expect(result.keys).to match_array(existing_token_values)
      end
    end

    context 'with unknown token type' do
      let(:token_value) { 'glpat-00000000000000000000' }
      let(:personal_access_token) { create(:personal_access_token) }

      before do
        personal_access_token.update_column(:token_digest, Gitlab::CryptoHelper.sha256(token_value))
      end

      it 'returns nil' do
        result = service.find('unknown_token_type', [token_value])

        expect(result).to be_nil
      end
    end

    context 'when token not found in database' do
      it 'returns an empty collection' do
        result = service.find('gitlab_personal_access_token', ['glpat-nonexistenttoken12345'])

        expect(result).to be_empty
      end
    end
  end

  describe '.supported_token_type?' do
    it 'returns true for supported token type' do
      expect(described_class.supported_token_type?('gitlab_personal_access_token')).to be true
    end

    it 'returns false for unsupported token type' do
      expect(described_class.supported_token_type?('unknown_token_type')).to be false
    end
  end

  describe '.enabled_targets_for' do
    it 'returns every target for an unrestricted token type' do
      expect(described_class.enabled_targets_for('gitlab_personal_access_token'))
        .to eq(Security::SecretDetection::Scanners::ALL)
    end

    it 'returns no targets for an unsupported token type' do
      expect(described_class.enabled_targets_for('unknown_token_type')).to eq([])
    end
  end

  describe 'TOKEN_TYPE_CONFIG' do
    using RSpec::Parameterized::TableSyntax

    where(:token_type, :enabled_targets) do
      'gitlab_personal_access_token'                    | Security::SecretDetection::Scanners::ALL
      'gitlab_personal_access_token_routable'           | Security::SecretDetection::Scanners::ALL
      'gitlab_personal_access_token_routable_versioned' | Security::SecretDetection::Scanners::ALL
      'gitlab_deploy_token'                             | Security::SecretDetection::Scanners::ALL
      'gitlab_runner_auth_token'                        | Security::SecretDetection::Scanners::ALL
      'gitlab_runner_auth_token_routable'               | Security::SecretDetection::Scanners::ALL
      'gitlab_kubernetes_agent_token'                   | Security::SecretDetection::Scanners::ALL
      'gitlab_scim_oauth_token'                         | Security::SecretDetection::Scanners::ALL
      'gitlab_ci_build_token'                           | Security::SecretDetection::Scanners::ALL
      'gitlab_incoming_email_token'                     | Security::SecretDetection::Scanners::ALL
      'gitlab_feed_token_v2'                            | Security::SecretDetection::Scanners::ALL
      'gitlab_pipeline_trigger_token'                   | Security::SecretDetection::Scanners::ALL
      'gitlab_oauth_app_secret'                         | Security::SecretDetection::Scanners::ALL
    end

    with_them do
      it 'declares the expected enabled targets' do
        config = described_class::TOKEN_TYPE_CONFIG.fetch(token_type)

        expect(config.fetch(:enabled_targets)).to eq(enabled_targets)
      end
    end

    it 'asserts a value for every configured token type' do
      asserted_token_types = %w[
        gitlab_personal_access_token
        gitlab_personal_access_token_routable
        gitlab_personal_access_token_routable_versioned
        gitlab_deploy_token
        gitlab_runner_auth_token
        gitlab_runner_auth_token_routable
        gitlab_kubernetes_agent_token
        gitlab_scim_oauth_token
        gitlab_ci_build_token
        gitlab_incoming_email_token
        gitlab_feed_token_v2
        gitlab_pipeline_trigger_token
        gitlab_oauth_app_secret
      ]

      expect(described_class::TOKEN_TYPE_CONFIG.keys).to match_array(asserted_token_types)
    end
  end
end
