# frozen_string_literal: true

module Security
  module SecretDetection
    module PartnerTokens
      class Registry
        RegistryError = Class.new(StandardError)
        UnsupportedTokenTypeError = Class.new(RegistryError)

        PARTNERS = {
          'AWS' => {
            client_class: ::Security::SecretDetection::PartnerTokens::AwsClient,
            rate_limit_key: :partner_aws_api,
            enabled: true,
            enabled_targets: Scanners::ALL
          }.freeze,
          # GCP - multiple rule types
          'GCP API key' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Gcp::ApiKey,
            rate_limit_key: :partner_gcp_api,
            enabled: true,
            enabled_targets: Scanners::ALL
          }.freeze,
          'GCP OAuth client secret' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Gcp::OauthClientSecret,
            rate_limit_key: :partner_gcp_api,
            enabled: true,
            enabled_targets: Scanners::ALL
          }.freeze,
          'Google (GCP) Service-account' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Gcp::ServiceAccount,
            rate_limit_key: :partner_gcp_api,
            enabled: true,
            enabled_targets: Scanners::ALL
          }.freeze,
          # Postman
          'Postman API token' => {
            client_class: ::Security::SecretDetection::PartnerTokens::PostmanClient,
            rate_limit_key: :partner_postman_api,
            enabled: true,
            enabled_targets: Scanners::ALL
          }.freeze,
          # GitHub
          'Github Personal Access Token' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Github::PersonalAccessToken,
            rate_limit_key: :partner_github_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'GithubFineGrainedPersonalAccessToken' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Github::FineGrainedPersonalAccessToken,
            rate_limit_key: :partner_github_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'Github OAuth Access Token' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Github::OauthAccessToken,
            rate_limit_key: :partner_github_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'GithubAppInstallationToken' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Github::AppInstallationToken,
            rate_limit_key: :partner_github_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          # OpenAI
          'OpenAiProjectKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Openai::ProjectKey,
            rate_limit_key: :partner_openai_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'OpenAiServiceAccountKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Openai::ServiceAccountKey,
            rate_limit_key: :partner_openai_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'OpenAiServiceAdminKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Openai::AdminKey,
            rate_limit_key: :partner_openai_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'open ai token' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Openai::UserApiKey,
            rate_limit_key: :partner_openai_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          # Anthropic
          'anthropic_key' => {
            client_class: ::Security::SecretDetection::PartnerTokens::AnthropicClient,
            rate_limit_key: :partner_anthropic_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          # Heroku
          'Heroku API Key' => {
            client_class: ::Security::SecretDetection::PartnerTokens::HerokuClient,
            rate_limit_key: :partner_heroku_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          # Stripe
          'StripeLiveSecretKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::LiveSecretKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeLiveRestrictedKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::LiveRestrictedKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeLivePublishableKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::LivePublishableKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeLiveShortSecretKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::LiveShortSecretKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeTestSecretKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::TestSecretKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeTestRestrictedKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::TestRestrictedKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeTestPublishableKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::TestPublishableKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          'StripeTestShortSecretKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::Stripe::TestShortSecretKey,
            rate_limit_key: :partner_stripe_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          # Datadog
          'DataDogAPIKey' => {
            client_class: ::Security::SecretDetection::PartnerTokens::DatadogClient,
            rate_limit_key: :partner_datadog_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze,
          # SendGrid
          'Sendgrid API token' => {
            client_class: ::Security::SecretDetection::PartnerTokens::SendgridClient,
            rate_limit_key: :partner_sendgrid_api,
            enabled: true,
            enabled_targets: [Scanners::GSS].freeze
          }.freeze
        }.freeze

        class << self
          def partner_for(token_type)
            config = PARTNERS[token_type.to_s]
            return unless config && config[:enabled]

            config
          end

          def client_for(token_type)
            config = partner_for(token_type)
            return unless config

            config[:client_class].new
          rescue NameError => e
            Gitlab::ErrorTracking.track_exception(
              e,
              token_type: token_type,
              client_class: config[:client_class]
            )
            nil
          end

          def rate_limit_key_for(token_type)
            config = partner_for(token_type)
            return unless config

            config[:rate_limit_key]
          end

          def enabled_targets_for(token_type)
            config = partner_for(token_type)
            return [] unless config

            config.fetch(:enabled_targets)
          end
        end
      end
    end
  end
end
