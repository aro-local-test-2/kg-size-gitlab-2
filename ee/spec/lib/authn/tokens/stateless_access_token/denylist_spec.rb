# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::Tokens::StatelessAccessToken::Denylist, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  def token_double(id: 'some-jti', expires_at: 1.hour.from_now)
    instance_double(Authn::Tokens::StatelessAccessToken, id: id, expires_at: expires_at)
  end

  describe '.denied?' do
    it 'returns false for a jti that was never denied' do
      expect(described_class.denied?('unknown-jti')).to be(false)
    end

    it 'returns false for a blank jti' do
      expect(described_class.denied?(nil)).to be(false)
    end

    it 'returns true once the jti has been denied' do
      described_class.deny!(token_double)

      expect(described_class.denied?('some-jti')).to be(true)
    end
  end

  describe '.deny!' do
    it 'sets a TTL matching the token remaining life, not a caller-supplied value' do
      described_class.deny!(token_double(expires_at: 30.seconds.from_now))

      ttl = ::Gitlab::Redis::SharedState.with { |redis| redis.ttl("stateless_access_token:revoked:some-jti") }

      expect(ttl).to be_between(1, 30)
    end

    it 'clamps to at least 1 second for a token at or past expiry' do
      described_class.deny!(token_double(expires_at: 1.hour.ago))

      expect(described_class.denied?('some-jti')).to be(true)
    end

    it 'does not deny a blank jti' do
      described_class.deny!(token_double(id: nil))
      described_class.deny!(token_double(id: ''))

      expect(described_class.denied?(nil)).to be(false)
      expect(described_class.denied?('')).to be(false)
    end

    it 'does not raise for a nil token' do
      expect { described_class.deny!(nil) }.not_to raise_error
    end
  end
end
