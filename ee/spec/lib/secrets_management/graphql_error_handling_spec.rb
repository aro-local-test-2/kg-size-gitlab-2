# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::GraphqlErrorHandling, feature_category: :secrets_management do
  let(:api_error_class) { Class.new(StandardError) }
  let(:dummy_class) do
    Class.new do
      include SecretsManagement::GraphqlErrorHandling

      def initialize(message)
        @message = message
      end

      def resolve
        raise SecretsManagement::SecretsManagerClient::ApiError, @message
      end

      def raise_resource_not_available_error!
        msg = Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
        raise Gitlab::Graphql::Errors::ResourceNotAvailable, msg # rubocop:disable Graphql/ResourceNotAvailableError -- we are mocking exactly the same method
      end
    end
  end

  before do
    stub_const('SecretsManagement::SecretsManagerClient::ApiError', api_error_class)
  end

  subject(:dummy) { dummy_class.new(error_message) }

  describe 'permission errors' do
    using RSpec::Parameterized::TableSyntax

    where(:error_message) do
      [
        'Unauthorized: missing token',
        'permission denied',
        'FORBIDDEN: blocked by policy',
        'error executing cel program: Cel "all" blocked authorization'
      ]
    end

    with_them do
      it 'raises ResourceNotAvailable' do
        msg = Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
        expect { dummy.resolve }
          .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable, msg)
      end
    end
  end

  describe 'mapped non-permission errors' do
    let(:error_message) { 'path is already in use' }

    it 'raises BaseError with mapped message' do
      expect { dummy.resolve }
        .to raise_error(Gitlab::Graphql::Errors::BaseError, SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end
  end

  describe 'unmapped errors' do
    let(:error_message) { 'some unexpected low-level driver error' }

    it 'raises BaseError with default message and reports to Sentry' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(instance_of(SecretsManagement::SecretsManagerClient::ApiError))

      expect { dummy.resolve }
        .to raise_error(Gitlab::Graphql::Errors::BaseError,
          SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end
  end

  describe 'not found errors' do
    let(:error_message) { SecretsManagement::ErrorMapping::NOT_FOUND_ERROR_MESSAGE }

    it 'raises ResourceNotAvailable and does not report to Sentry' do
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      msg = Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
      expect { dummy.resolve }
        .to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable, msg)
    end
  end

  describe 'a namespace-not-found error' do
    let(:error_message) { 'namespace not found' }

    it 'still reports to Sentry, because only the bare message is an absent resource' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
              .with(instance_of(SecretsManagement::SecretsManagerClient::ApiError))

      expect { dummy.resolve }
        .to raise_error(Gitlab::Graphql::Errors::BaseError,
          SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end
  end

  describe 'an error whose message quotes the OpenBao path' do
    let(:error_message) { 'no handler for route "secrets/kv/data/explicit/MY_DB_PASSWORD". route entry not found.' }

    it 'reports it with the path redacted and the diagnostic text kept', :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception) do |reported|
        expect(reported).to be_a(SecretsManagement::SecretsManagerClient::ApiError)
        expect(reported.message).not_to include('MY_DB_PASSWORD')
        expect(reported.message).to include('route entry not found')
      end

      expect { dummy.resolve }
        .to raise_error(Gitlab::Graphql::Errors::BaseError,
          SecretsManagement::ErrorMapping::DEFAULT_ERROR_MESSAGE)
    end
  end

  describe 'CAS error' do
    let(:error_message) { 'metadata check-and-set parameter does not match' }

    it 'raises BaseError and does not report to Sentry' do
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect { dummy.resolve }
        .to raise_error(Gitlab::Graphql::Errors::BaseError)
    end
  end
end
