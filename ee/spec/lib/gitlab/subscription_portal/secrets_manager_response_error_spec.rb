# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SubscriptionPortal::SecretsManagerResponseError, feature_category: :secrets_management do
  describe 'UNAVAILABLE_STATUSES' do
    it 'covers the 5xx statuses CDot answers with, none of which is a decision' do
      expect(described_class::UNAVAILABLE_STATUSES).to contain_exactly(500, 502, 503, 504)
    end
  end

  # The list re-states part of Gitlab::HTTP::HTTP_ERRORS by hand, and a class missing
  # from it denies access during the outage it was meant to cover. Pin the complement.
  describe '.unavailable_transport_errors' do
    it 'accounts for every error the client can wrap' do
      not_unavailable = ::Gitlab::HTTP::HTTP_ERRORS - described_class.unavailable_transport_errors

      expect(not_unavailable).to contain_exactly(
        OpenSSL::OpenSSLError,
        Net::HTTPBadResponse,
        ::Gitlab::HTTP_V2::BlockedUrlError,
        ::Gitlab::HTTP_V2::RedirectionTooDeep,
        ::Gitlab::HTTP_V2::ResponseSizeTooLarge,
        ::Gitlab::HTTP_V2::MaxDecompressionSizeError,
        ::Gitlab::HTTP_V2::InvalidResponseError,
        ::Gitlab::HTTP_V2::HeaderInjectionError
      )
    end
  end

  describe '.unavailable_transport?' do
    it 'is true for a timeout, a refused connection, and a bad hostname', :aggregate_failures do
      expect(described_class.unavailable_transport?(Net::ReadTimeout.new)).to be true
      expect(described_class.unavailable_transport?(Errno::ECONNREFUSED.new)).to be true
      expect(described_class.unavailable_transport?(SocketError.new)).to be true
    end

    it 'is false for our own guards and for non-transport errors', :aggregate_failures do
      expect(described_class.unavailable_transport?(::Gitlab::HTTP_V2::BlockedUrlError.new)).to be false
      expect(described_class.unavailable_transport?(Net::HTTPBadResponse.new)).to be false
      expect(described_class.unavailable_transport?(StandardError.new)).to be false
    end
  end

  describe '#initialize' do
    it 'carries the status and block_reason CDot answered with', :aggregate_failures do
      error = described_class.new('HTTP 403', cdot_status: 403, cdot_block_reason: 'resolution_error')

      expect(error.message).to eq('HTTP 403')
      expect(error.cdot_status).to eq(403)
      expect(error.cdot_block_reason).to eq('resolution_error')
    end

    it 'defaults both to nil, so the client can still wrap a transport error by message alone',
      :aggregate_failures do
      error = described_class.new('connection refused')

      expect(error.cdot_status).to be_nil
      expect(error.cdot_block_reason).to be_nil
    end

    it 'accepts `raise klass, message`, which callers rescuing the base class rely on' do
      expect { raise described_class, 'boom' }.to raise_error(described_class, 'boom')
    end
  end

  describe '.unavailable_status?' do
    it 'is true for the 5xx CDot answers with and false for explicit answers', :aggregate_failures do
      described_class::UNAVAILABLE_STATUSES.each do |code|
        expect(described_class.unavailable_status?(code)).to be true
      end

      [200, 400, 402, 403, 422].each do |code|
        expect(described_class.unavailable_status?(code)).to be false
      end
    end
  end

  # The resolver and the mutations rescue this class and check for UnavailableError, so
  # both the per-endpoint Error classes and the shared UnavailableError must sit under it.
  describe 'hierarchy' do
    it 'is the ancestor of the per-endpoint Error classes and of UnavailableError', :aggregate_failures do
      expect(Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error.superclass).to eq(described_class)
      expect(Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error.superclass)
        .to eq(described_class)
      expect(described_class::UnavailableError.superclass).to eq(described_class)
    end
  end
end
