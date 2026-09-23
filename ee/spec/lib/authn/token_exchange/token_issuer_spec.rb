# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::TokenExchange::TokenIssuer, feature_category: :system_access do
  let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
  let_it_be(:user) { create(:user) }

  let(:audiences) { ['gitlab-artifact-registry'] }
  let(:ttl) { 300 }
  let(:organization) { user.organization }

  before do
    # CachingKeyLoader memoizes Keys.current at the class level, which leaks
    # across specs when other specs also create keys. Pin it to ours.
    allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk)
      .and_return(cloud_connector_key.to_jwk)
    allow(Doorkeeper::OpenidConnect.configuration).to receive(:issuer)
      .and_return('http://test.host/oauth-issuer')
  end

  subject(:issuer) do
    described_class.new(audiences: audiences, user: user, organization: organization, ttl: ttl)
  end

  describe '#token' do
    it 'returns a signed JWT with the expected claim shape', :aggregate_failures do
      token = issuer.token

      payload, header = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(header).to include('typ' => 'JWT', 'alg' => 'RS256')
      expect(header['kid']).to eq(cloud_connector_key.to_jwk.kid)

      expect(payload).to include(
        'iss' => 'http://test.host/oauth-issuer',
        'aud' => %w[gitlab-artifact-registry],
        'sub' => user.to_global_id.to_s,
        'ver' => 1
      )
      expect(payload['gitlab']).to include(
        'token_type' => described_class::TOKEN_TYPE,
        'origin' => 'organization',
        'origin_id' => user.organization.uuid,
        'local_id' => user.id,
        'identity_kind' => 'user',
        'organization_role' => 'member'
      )
      expect(payload['jti']).to match(/\A[0-9a-f-]{36}\z/)

      %w[gitlab_realm gitlab_organization_id gitlab_organization_role].each do |removed|
        expect(payload).not_to have_key(removed)
      end
    end

    it 'passes through exactly the audiences the caller gives it, e.g. a data-access audience' do
      token = described_class.new(
        audiences: ['gitlab-artifact-registry', described_class::DATA_ACCESS_AUDIENCE],
        user: user, organization: organization
      ).token
      payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(payload['aud']).to match_array(['gitlab-artifact-registry', described_class::DATA_ACCESS_AUDIENCE])
    end

    it 'coerces a String audiences value to an array' do
      token = described_class.new(
        audiences: 'gitlab-artifact-registry', user: user, organization: organization
      ).token
      payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(payload['aud']).to match_array(['gitlab-artifact-registry'])
    end

    it 'deduplicates a repeated audience value' do
      token = described_class.new(
        audiences: %w[gitlab-artifact-registry gitlab-artifact-registry],
        user: user, organization: organization
      ).token
      payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(payload['aud']).to eq(['gitlab-artifact-registry'])
    end

    it 'raises when audiences is empty' do
      expect do
        described_class.new(audiences: [], user: user, organization: organization)
      end.to raise_error(ArgumentError, 'audiences must not be empty')
    end

    it 'raises when audiences is nil' do
      expect do
        described_class.new(audiences: nil, user: user, organization: organization)
      end.to raise_error(ArgumentError, 'audiences must not be empty')
    end

    it 'sets iat, nbf, and exp', :freeze_time, :aggregate_failures do
      token = issuer.token
      payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(payload['iat']).to eq(Time.current.to_i)
      expect(payload['nbf']).to eq(Time.current.to_i)
      expect(payload['exp']).to eq(Time.current.to_i + ttl)
    end

    it 'defaults exp to DEFAULT_TTL_SECONDS when ttl is omitted', :freeze_time do
      token = described_class.new(audiences: audiences, user: user, organization: organization).token
      payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

      expect(payload['exp']).to eq(Time.current.to_i + described_class::DEFAULT_TTL_SECONDS)
    end

    it 'generates a fresh jti per mint' do
      jti1 = JWT.decode(issuer.token, nil, false).first['jti']
      jti2 = JWT.decode(issuer.token, nil, false).first['jti']

      expect(jti1).not_to eq(jti2)
    end

    describe 'organization_role claim' do
      def decoded_role(for_user, for_organization = nil)
        token = described_class.new(
          audiences: audiences, user: for_user, organization: for_organization || for_user.organization, ttl: ttl
        ).token
        decoded = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256').first
        decoded.dig('gitlab', 'organization_role')
      end

      it "emits 'member' when the user does not own the organization" do
        expect(decoded_role(user)).to eq('member')
      end

      it "emits 'owner' when the user owns the organization" do
        owner = create(:user)
        owner.organization_users.find_by(organization: owner.organization).update!(access_level: :owner)

        expect(decoded_role(owner)).to eq('owner')
      end

      # IAM keys a principal on (origin, origin_id, local_id), so the
      # organization passed in decides which principal the token resolves to.
      # It is not the user's home organization.
      it 'answers for the organization passed in, not the home one' do
        other = create(:organization)
        create(:organization_user, :owner, organization: other, user: user)

        expect(decoded_role(user)).to eq('member')
        expect(decoded_role(user, other)).to eq('owner')
      end

      it 'puts the given organization uuid in origin_id' do
        other = create(:organization)
        token = described_class.new(audiences: audiences, user: user, organization: other, ttl: ttl).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload.dig('gitlab', 'origin_id')).to eq(other.uuid)
        expect(payload.dig('gitlab', 'origin_id')).not_to eq(user.organization.uuid)
      end
    end

    describe 'scopes claim (gitlab.scopes)' do
      it 'omits the scopes key when no scopes are provided' do
        payload, = JWT.decode(issuer.token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']).not_to have_key('scopes')
      end

      it 'embeds scopes as strings when provided' do
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, scopes: [:ai_workflows, :mcp]
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']['scopes']).to contain_exactly('ai_workflows', 'mcp')
      end
    end

    describe 'identities claim (gitlab.identities)' do
      let_it_be(:human_user) { create(:user) }

      it 'omits the identities key when no identities are provided' do
        payload, = JWT.decode(issuer.token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']).not_to have_key('identities')
      end

      it 'embeds identities when provided' do
        identity = { kind: 'user', local_id: human_user.id }
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, identities: [identity]
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']['identities']).to contain_exactly(
          { 'kind' => 'user', 'local_id' => human_user.id }
        )
      end

      it 'wraps a bare Hash as a single identity instead of flattening it' do
        identity = { kind: 'user', local_id: human_user.id }
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, identities: identity
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']['identities']).to contain_exactly(
          { 'kind' => 'user', 'local_id' => human_user.id }
        )
      end
    end

    describe 'build provenance claims (gitlab.job)' do
      it 'omits the job key when no job is provided' do
        payload, = JWT.decode(issuer.token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']).not_to have_key('job')
      end

      it 'embeds the job project id and commit sha when a job is provided', :aggregate_failures do
        job = build_stubbed(:ci_build)
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, job: job
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['gitlab']['job']).to eq('project_id' => job.project_id, 'git_commit_sha' => job.sha)
        expect(payload['ver']).to eq(1)
      end
    end

    describe 'routing claims (top-level c/o/u/p/g/t)' do
      it 'omits routing claims when none are provided' do
        payload, = JWT.decode(issuer.token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload.keys & %w[c o u p g t]).to be_empty
      end

      it 'base36-encodes provided routing claims as top-level keys' do
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, routing: { o: 42, u: 7 }
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['o']).to eq(42.to_s(36))
        expect(payload['u']).to eq(7.to_s(36))
      end

      it 'accepts t (runner type) as a routing claim' do
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, routing: { t: 2 }
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['t']).to eq(2.to_s(36))
      end

      it 'drops routing keys outside the c/o/u/p/g/t allow-list', :freeze_time do
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, ttl: ttl, routing: { exp: 0, o: 42 }
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['exp']).to eq(Time.current.to_i + ttl)
        expect(payload['o']).to eq(42.to_s(36))
      end

      it 'accepts string-keyed routing entries the same as symbol keys' do
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, routing: { 'o' => 42 }
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['o']).to eq(42.to_s(36))
      end

      it 'drops a nil-valued routing entry instead of raising' do
        token = described_class.new(
          audiences: audiences, user: user, organization: organization, routing: { o: 42, g: nil }
        ).token
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['o']).to eq(42.to_s(36))
        expect(payload).not_to have_key('g')
      end
    end
  end
end
