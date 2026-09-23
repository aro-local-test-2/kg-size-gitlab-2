# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::Tokens::StatelessAccessToken, :clean_gitlab_redis_shared_state, feature_category: :duo_agent_platform do
  let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
  let_it_be(:user) { create(:user) }
  let_it_be(:human_user) { create(:user) }
  let_it_be(:organization) { create(:organization) }

  let(:issuer) { 'http://test.host/oauth-issuer' }
  let(:ttl) { 1.hour.to_i }
  let(:scopes) { %w[ai_workflows mcp] }
  let(:identities) { [{ kind: 'user', local_id: human_user.id }] }

  before do
    allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
    allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
    allow(Doorkeeper::OpenidConnect.configuration).to receive(:issuer).and_return(issuer)
  end

  def issue_result(user: self.user, extra_scopes: scopes, extra_identities: identities, routing: {})
    described_class.issue(
      user: user, organization: organization, ttl: ttl, scopes: extra_scopes, identities: extra_identities,
      routing: routing
    )
  end

  def issue_token(**kwargs)
    issue_result(**kwargs).plaintext_token
  end

  # Builds a raw, correctly-signed JWT bypassing TokenIssuer, so tests can
  # assert on claims (aud, iss) that .issue always sets correctly.
  # A `gitlab:` override replaces the default wholesale (like every other
  # claim here), so tests overriding `gitlab` for an unrelated reason must
  # re-include `token_type` themselves or the token_type check will reject
  # the token before reaching the behavior under test.
  def encode_raw_jwt(omit: [], **claim_overrides)
    jwk = cloud_connector_key.to_jwk
    now = Time.current.to_i
    payload = {
      jti: SecureRandom.uuid,
      iss: issuer,
      aud: [described_class::RAILS_AUDIENCE],
      sub: user.to_global_id.to_s,
      iat: now,
      nbf: now,
      exp: now + ttl,
      ver: 1,
      gitlab: { token_type: Authn::TokenExchange::TokenIssuer::TOKEN_TYPE }
    }.merge(claim_overrides).except(*omit)

    jwt = JWT.encode(payload, jwk.signing_key, 'RS256', { typ: 'JWT', kid: jwk.kid })
    "#{described_class::TOKEN_PREFIX}#{jwt}"
  end

  describe '.issue' do
    it 'prepends the StatelessAccessToken prefix' do
      expect(issue_token).to start_with(described_class::TOKEN_PREFIX)
    end

    it 'returns a result exposing scopes, expires_in and expires_at', :freeze_time do
      result = issue_result

      expect(result.scopes).to eq(scopes)
      expect(result.expires_in).to eq(ttl)
      expect(result.expires_at).to eq(ttl.seconds.from_now)
    end

    it 'embeds routing claims when provided' do
      stub_config(cell: { enabled: true, id: 1 })

      token_string = issue_token(routing: { o: organization.id, u: user.id })
      jwt_string = token_string.delete_prefix(described_class::TOKEN_PREFIX)
      payload, = JWT.decode(jwt_string, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(payload['o']).to eq(organization.id.to_s(36))
      expect(payload['u']).to eq(user.id.to_s(36))
      expect(payload['c']).to eq(1.to_s(36))
    end
  end

  describe '.from_jwt' do
    subject(:token) { described_class.from_jwt(token_string) }

    context 'when the string is not a StatelessAccessToken' do
      it 'returns nil for nil' do
        expect(described_class.from_jwt(nil)).to be_nil
      end

      it 'returns nil for a plain string' do
        expect(described_class.from_jwt('not-a-token')).to be_nil
      end

      it 'returns nil for an unprefixed JWT' do
        bare_jwt = issue_token.delete_prefix(described_class::TOKEN_PREFIX)

        expect(described_class.from_jwt(bare_jwt)).to be_nil
      end

      it 'returns nil for a malformed JWT following a valid prefix' do
        expect(described_class.from_jwt("#{issue_token}-corrupted")).to be_nil
      end
    end

    context 'when the JWT audience does not match RAILS_AUDIENCE' do
      let(:token_string) { encode_raw_jwt(aud: ['some-other-audience']) }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT issuer does not match' do
      let(:token_string) { encode_raw_jwt(iss: 'http://attacker.example/oauth-issuer') }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'with a valid token' do
      let(:token_string) { issue_token }

      it 'returns a StatelessAccessToken instance' do
        is_expected.to be_a(described_class)
      end

      it 'resolves the correct user_id from the sub GlobalID' do
        expect(token.user_id).to eq(user.id)
      end

      it 'exposes scopes as a Doorkeeper::OAuth::Scopes instance', :aggregate_failures do
        expect(token.scopes).to be_a(Doorkeeper::OAuth::Scopes)
        expect(token.scopes.to_a).to contain_exactly('ai_workflows', 'mcp')
      end

      it 'exposes identity_user from the identities claim' do
        expect(token.identity_user).to eq(human_user)
      end

      it 'exposes scope_user as an alias for identity_user' do
        expect(token.scope_user).to eq(human_user)
      end

      it 'is not expired' do
        expect(token).not_to be_expired
      end

      it 'is active' do
        expect(token).to be_active
      end

      it 'is not revoked' do
        expect(token).not_to be_revoked
      end
    end

    context 'when the JWT is expired' do
      let(:ttl) { -1 }
      let(:token_string) { issue_token }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT has no identities claim (simple flow)' do
      let(:token_string) { issue_token(extra_identities: []) }

      it 'returns a token with nil identity_user' do
        expect(token).to be_a(described_class)
        expect(token.identity_user).to be_nil
      end
    end

    context 'when the composite identity user cannot be resolved (e.g. deleted)' do
      let(:deleted_user_id) { non_existing_record_id }
      let(:token_string) { issue_token(extra_identities: [{ kind: 'user', local_id: deleted_user_id }]) }

      it 'returns nil rather than falling back to gating on the service account' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT has more than one kind:user identity entry' do
      let(:other_user) { create(:user) }
      let(:token_string) do
        issue_token(extra_identities: [
          { kind: 'user', local_id: human_user.id },
          { kind: 'user', local_id: other_user.id }
        ])
      end

      it 'rejects the token, as identity_user is ambiguous and the gating user cannot be resolved' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT payload is missing the exp claim entirely' do
      let(:token_string) { encode_raw_jwt(omit: [:exp]) }

      it 'returns nil instead of raising' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT payload is missing the jti claim entirely' do
      let(:token_string) { encode_raw_jwt(omit: [:jti]) }

      it 'returns nil instead of raising' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT payload is missing the iat claim entirely' do
      let(:token_string) { encode_raw_jwt(omit: [:iat]) }

      it 'returns nil instead of raising' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT gitlab.token_type does not match TokenIssuer::TOKEN_TYPE' do
      let(:token_string) { encode_raw_jwt(gitlab: { token_type: 'some-other-type' }) }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT gitlab.token_type claim is missing' do
      let(:token_string) { encode_raw_jwt(gitlab: {}) }

      it 'returns nil' do
        is_expected.to be_nil
      end
    end

    context 'when the identities claim contains a non-Hash entry' do
      let(:token_string) do
        encode_raw_jwt(gitlab: {
          token_type: Authn::TokenExchange::TokenIssuer::TOKEN_TYPE,
          identities: [{ kind: 'user', local_id: human_user.id }, 'not-a-hash']
        })
      end

      it 'returns nil instead of raising' do
        is_expected.to be_nil
      end
    end

    context 'when the JWT has been revoked' do
      let(:token_string) { issue_token }

      it 'is revoked once the jti is denylisted' do
        expect(token).to be_active

        Authn::Tokens::StatelessAccessToken::Denylist.deny!(token)

        expect(described_class.from_jwt(token_string)).to be_revoked
      end
    end
  end

  describe '#resource_owner_id' do
    subject(:token) { described_class.from_jwt(issue_token) }

    it 'returns user_id' do
      expect(token.resource_owner_id).to eq(user.id)
    end
  end

  describe '#acceptable?' do
    subject(:token) { described_class.from_jwt(issue_token) }

    it 'accepts a scope the token carries' do
      expect(token.acceptable?('ai_workflows')).to be(true)
    end

    it 'rejects a scope the token does not carry' do
      expect(token.acceptable?('admin_mode')).to be(false)
    end
  end
end
