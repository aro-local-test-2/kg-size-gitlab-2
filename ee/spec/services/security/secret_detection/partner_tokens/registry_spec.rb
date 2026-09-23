# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Registry, feature_category: :secret_detection do
  describe 'PARTNERS configuration' do
    using RSpec::Parameterized::TableSyntax

    where(:token_type, :client_class, :rate_limit_key, :enabled_targets) do
      'AWS' |
        ::Security::SecretDetection::PartnerTokens::AwsClient |
        :partner_aws_api |
        Security::SecretDetection::Scanners::ALL
      'GCP API key' |
        ::Security::SecretDetection::PartnerTokens::Gcp::ApiKey |
        :partner_gcp_api |
        Security::SecretDetection::Scanners::ALL
      'GCP OAuth client secret' |
        ::Security::SecretDetection::PartnerTokens::Gcp::OauthClientSecret |
        :partner_gcp_api |
        Security::SecretDetection::Scanners::ALL
      'Google (GCP) Service-account' |
        ::Security::SecretDetection::PartnerTokens::Gcp::ServiceAccount |
        :partner_gcp_api |
        Security::SecretDetection::Scanners::ALL
      'Postman API token' |
        ::Security::SecretDetection::PartnerTokens::PostmanClient |
        :partner_postman_api |
        Security::SecretDetection::Scanners::ALL
      'Github Personal Access Token' |
        ::Security::SecretDetection::PartnerTokens::Github::PersonalAccessToken |
        :partner_github_api |
        [Security::SecretDetection::Scanners::GSS]
      'GithubFineGrainedPersonalAccessToken' |
        ::Security::SecretDetection::PartnerTokens::Github::FineGrainedPersonalAccessToken |
        :partner_github_api |
        [Security::SecretDetection::Scanners::GSS]
      'Github OAuth Access Token' |
        ::Security::SecretDetection::PartnerTokens::Github::OauthAccessToken |
        :partner_github_api |
        [Security::SecretDetection::Scanners::GSS]
      'GithubAppInstallationToken' |
        ::Security::SecretDetection::PartnerTokens::Github::AppInstallationToken |
        :partner_github_api |
        [Security::SecretDetection::Scanners::GSS]
      'OpenAiProjectKey' |
        ::Security::SecretDetection::PartnerTokens::Openai::ProjectKey |
        :partner_openai_api |
        [Security::SecretDetection::Scanners::GSS]
      'OpenAiServiceAccountKey' |
        ::Security::SecretDetection::PartnerTokens::Openai::ServiceAccountKey |
        :partner_openai_api |
        [Security::SecretDetection::Scanners::GSS]
      'OpenAiServiceAdminKey' |
        ::Security::SecretDetection::PartnerTokens::Openai::AdminKey |
        :partner_openai_api |
        [Security::SecretDetection::Scanners::GSS]
      'open ai token' |
        ::Security::SecretDetection::PartnerTokens::Openai::UserApiKey |
        :partner_openai_api |
        [Security::SecretDetection::Scanners::GSS]
      'anthropic_key' |
        ::Security::SecretDetection::PartnerTokens::AnthropicClient |
        :partner_anthropic_api |
        [Security::SecretDetection::Scanners::GSS]
      'Heroku API Key' |
        ::Security::SecretDetection::PartnerTokens::HerokuClient |
        :partner_heroku_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeLiveSecretKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::LiveSecretKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeLiveRestrictedKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::LiveRestrictedKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeLivePublishableKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::LivePublishableKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeLiveShortSecretKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::LiveShortSecretKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeTestSecretKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::TestSecretKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeTestRestrictedKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::TestRestrictedKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeTestPublishableKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::TestPublishableKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'StripeTestShortSecretKey' |
        ::Security::SecretDetection::PartnerTokens::Stripe::TestShortSecretKey |
        :partner_stripe_api |
        [Security::SecretDetection::Scanners::GSS]
      'DataDogAPIKey' |
        ::Security::SecretDetection::PartnerTokens::DatadogClient |
        :partner_datadog_api |
        [Security::SecretDetection::Scanners::GSS]
      'Sendgrid API token' |
        ::Security::SecretDetection::PartnerTokens::SendgridClient |
        :partner_sendgrid_api |
        [Security::SecretDetection::Scanners::GSS]
    end

    with_them do
      it 'has correct configuration' do
        config = described_class::PARTNERS[token_type]

        expect(config).to include(
          client_class: client_class,
          rate_limit_key: rate_limit_key,
          enabled: true,
          enabled_targets: enabled_targets
        )
      end
    end
  end

  describe '.partner_for' do
    shared_examples 'returns partner configuration' do |token_type|
      it 'returns the configuration hash' do
        config = described_class.partner_for(token_type)

        expect(config).to be_a(Hash)
        expect(config).to include(:client_class, :rate_limit_key, :enabled)
      end
    end

    shared_examples 'returns nil for invalid input' do |input|
      it 'returns nil' do
        expect(described_class.partner_for(input)).to be_nil
      end
    end

    context 'with valid token types' do
      ['AWS', 'GCP API key', 'GCP OAuth client secret', 'Google (GCP) Service-account',
        'Postman API token'].each do |token_type|
        it_behaves_like 'returns partner configuration', token_type
      end
    end

    context 'with invalid inputs' do
      it_behaves_like 'returns nil for invalid input', 'unknown_token'
      it_behaves_like 'returns nil for invalid input', nil
      it_behaves_like 'returns nil for invalid input', ''
      it_behaves_like 'returns nil for invalid input', 123
    end

    context 'with disabled partner' do
      before do
        stub_const("#{described_class}::PARTNERS", {
          'disabled_token' => {
            client_class: 'SomeClass',
            rate_limit_key: :some_key,
            enabled: false
          }
        })
      end

      it 'returns nil for disabled partners' do
        expect(described_class.partner_for('disabled_token')).to be_nil
      end
    end
  end

  describe '.client_for' do
    shared_examples 'instantiates client successfully' do |token_type, client_class|
      before do
        stub_const(client_class.name, Class.new)
      end

      it 'returns new instance of client class' do
        client = described_class.client_for(token_type)
        expect(client).to be_a(client_class)
      end
    end

    shared_examples 'handles missing client class' do |token_type|
      it 'tracks exception and returns nil' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(NameError), hash_including(:token_type, :client_class))

        expect(described_class.client_for(token_type)).to be_nil
      end
    end

    context 'with existing client classes' do
      it_behaves_like 'instantiates client successfully',
        'AWS',
        ::Security::SecretDetection::PartnerTokens::AwsClient
    end

    context 'with non-existent client classes' do
      before do
        stub_const("#{described_class}::PARTNERS", described_class::PARTNERS.merge(
          'fake_token' => {
            client_class: 'NonExistentClass',
            rate_limit_key: :fake_api,
            enabled: true
          }
        ))
      end

      it_behaves_like 'handles missing client class', 'fake_token'
    end

    context 'with unsupported token type' do
      it 'returns nil without tracking error' do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
        expect(described_class.client_for('unknown')).to be_nil
      end
    end
  end

  describe '.rate_limit_key_for' do
    using RSpec::Parameterized::TableSyntax

    where(:token_type, :expected_key) do
      'AWS'                                  | :partner_aws_api
      'GCP API key'                          | :partner_gcp_api
      'GCP OAuth client secret'              | :partner_gcp_api
      'Google (GCP) Service-account'         | :partner_gcp_api
      'Postman API token'                    | :partner_postman_api
      'Github Personal Access Token'         | :partner_github_api
      'GithubFineGrainedPersonalAccessToken' | :partner_github_api
      'Github OAuth Access Token'            | :partner_github_api
      'GithubAppInstallationToken'           | :partner_github_api
      'OpenAiProjectKey'                     | :partner_openai_api
      'OpenAiServiceAccountKey'              | :partner_openai_api
      'OpenAiServiceAdminKey'                | :partner_openai_api
      'open ai token'                        | :partner_openai_api
      'anthropic_key'                        | :partner_anthropic_api
      'Heroku API Key'                       | :partner_heroku_api
      'StripeLiveSecretKey'                  | :partner_stripe_api
      'StripeLiveRestrictedKey'              | :partner_stripe_api
      'StripeLivePublishableKey'             | :partner_stripe_api
      'StripeLiveShortSecretKey'             | :partner_stripe_api
      'StripeTestSecretKey'                  | :partner_stripe_api
      'StripeTestRestrictedKey'              | :partner_stripe_api
      'StripeTestPublishableKey'             | :partner_stripe_api
      'StripeTestShortSecretKey'             | :partner_stripe_api
      'DataDogAPIKey'                        | :partner_datadog_api
      'Sendgrid API token'                   | :partner_sendgrid_api
      'unknown_token'                        | nil
      nil | nil
    end

    with_them do
      it 'returns the correct rate limit key' do
        expect(described_class.rate_limit_key_for(token_type)).to eq(expected_key)
      end
    end
  end

  describe '.enabled_targets_for' do
    using RSpec::Parameterized::TableSyntax

    where(:token_type, :expected) do
      'AWS'                                  | Security::SecretDetection::Scanners::ALL
      'GCP API key'                          | Security::SecretDetection::Scanners::ALL
      'GCP OAuth client secret'              | Security::SecretDetection::Scanners::ALL
      'Google (GCP) Service-account'         | Security::SecretDetection::Scanners::ALL
      'Postman API token'                    | Security::SecretDetection::Scanners::ALL
      'Github Personal Access Token'         | [Security::SecretDetection::Scanners::GSS]
      'GithubFineGrainedPersonalAccessToken' | [Security::SecretDetection::Scanners::GSS]
      'Github OAuth Access Token'            | [Security::SecretDetection::Scanners::GSS]
      'GithubAppInstallationToken'           | [Security::SecretDetection::Scanners::GSS]
      'OpenAiProjectKey'                     | [Security::SecretDetection::Scanners::GSS]
      'OpenAiServiceAccountKey'              | [Security::SecretDetection::Scanners::GSS]
      'OpenAiServiceAdminKey'                | [Security::SecretDetection::Scanners::GSS]
      'open ai token'                        | [Security::SecretDetection::Scanners::GSS]
      'anthropic_key'                        | [Security::SecretDetection::Scanners::GSS]
      'Heroku API Key'                       | [Security::SecretDetection::Scanners::GSS]
      'StripeLiveSecretKey'                  | [Security::SecretDetection::Scanners::GSS]
      'StripeLiveRestrictedKey'              | [Security::SecretDetection::Scanners::GSS]
      'StripeLivePublishableKey'             | [Security::SecretDetection::Scanners::GSS]
      'StripeLiveShortSecretKey'             | [Security::SecretDetection::Scanners::GSS]
      'StripeTestSecretKey'                  | [Security::SecretDetection::Scanners::GSS]
      'StripeTestRestrictedKey'              | [Security::SecretDetection::Scanners::GSS]
      'StripeTestPublishableKey'             | [Security::SecretDetection::Scanners::GSS]
      'StripeTestShortSecretKey'             | [Security::SecretDetection::Scanners::GSS]
      'DataDogAPIKey'                        | [Security::SecretDetection::Scanners::GSS]
      'Sendgrid API token'                   | [Security::SecretDetection::Scanners::GSS]
      'unknown_token'                        | []
    end

    with_them do
      it 'returns the targets whose findings are verified' do
        expect(described_class.enabled_targets_for(token_type)).to eq(expected)
      end
    end

    it 'returns no targets for a nil token type' do
      expect(described_class.enabled_targets_for(nil)).to eq([])
    end
  end
end
