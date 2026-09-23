# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::TokenExchange, feature_category: :artifact_registry do
  let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
  let_it_be(:user) { create(:user) }
  let_it_be(:organization) { create(:organization) }

  subject(:token_exchange) { described_class.new }

  before do
    # CachingKeyLoader memoizes Keys.current at the class level, which leaks
    # across specs when other specs also create keys. Pin it to ours.
    allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk)
      .and_return(cloud_connector_key.to_jwk)
  end

  describe '#token_for' do
    context 'when the caller is a member of the addressed organization' do
      subject(:token) { token_exchange.token_for(user, organization) }

      before_all do
        create(:organization_user, organization: organization, user: user)
      end

      it 'mints a JWT the AR verifier accepts', :aggregate_failures do
        payload, header = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(header).to include('typ' => 'JWT', 'alg' => 'RS256')
        expect(payload).to include(
          'aud' => %w[gitlab-artifact-registry gitlab-iam-data-access],
          'sub' => user.to_global_id.to_s,
          'ver' => 1
        )
        expect(payload['gitlab']).to include('identity_kind' => 'user', 'local_id' => user.id)
      end

      it 'names the addressed organization, not the home one' do
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        # Core acceptance case (#626558): the organization the request addresses,
        # not the one that owns the account.
        expect(payload['gitlab']['origin_id']).to eq(organization.uuid)
      end

      it 'mints a token whose lifetime is the issuer default, not an override' do
        payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

        expect(payload['exp'] - payload['iat']).to eq(::Authn::TokenExchange::TokenIssuer::DEFAULT_TTL_SECONDS)
      end

      context 'when the caller also belongs to other Artifact Registry organizations' do
        let_it_be(:other_organizations) { create_list(:organization, 2) }

        before_all do
          other_organizations.each do |other|
            create(:artifact_registry_namespace_mapping, organization: other)
            create(:organization_user, organization: other, user: user)
          end
        end

        # Nothing to infer: the request already says which organization it addresses.
        it 'still names the addressed organization' do
          payload, = JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256')

          expect(payload['gitlab']['origin_id']).to eq(organization.uuid)
        end
      end

      describe 'memoization' do
        it 'mints once for repeated calls with the same user and organization', :aggregate_failures do
          expect(::Authn::TokenExchange::TokenIssuer).to receive(:new).once.and_call_original

          first = token_exchange.token_for(user, organization)
          second = token_exchange.token_for(user, organization)

          expect(first).to eq(second)
        end

        it 'mints a distinct token per user, so a shared instance cannot leak one user credential to another',
          :aggregate_failures do
          other_user = create(:user)
          create(:organization_user, organization: organization, user: other_user)

          first_sub = decode(token_exchange.token_for(user, organization))['sub']
          second_sub = decode(token_exchange.token_for(other_user, organization))['sub']

          expect(first_sub).to eq(user.to_global_id.to_s)
          expect(second_sub).to eq(other_user.to_global_id.to_s)
          expect(first_sub).not_to eq(second_sub)
        end

        it 'mints a distinct token per organization for the same user', :aggregate_failures do
          other_organization = create(:organization)
          create(:organization_user, organization: other_organization, user: user)

          first_origin = decode(token_exchange.token_for(user, organization))['gitlab']['origin_id']
          second_origin = decode(token_exchange.token_for(user, other_organization))['gitlab']['origin_id']

          expect(first_origin).to eq(organization.uuid)
          expect(second_origin).to eq(other_organization.uuid)
        end

        it 'does not share the memo across instances' do
          first_jti = decode(described_class.new.token_for(user, organization))['jti']
          second_jti = decode(described_class.new.token_for(user, organization))['jti']

          expect(first_jti).not_to eq(second_jti)
        end
      end

      context 'when the membership query raises a database fault' do
        before do
          allow(user).to receive(:member_of_organization?).and_raise(ActiveRecord::StatementInvalid, 'timeout')
        end

        it 'converts the fault to ConfigurationError instead of escaping as a 500', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(ActiveRecord::StatementInvalid), hash_including(artifact_registry_token_mint: true))

          expect { token_exchange.token_for(user, organization) }
            .to raise_error(::ArtifactRegistry::Client::ConfigurationError, /could not be minted/)
        end
      end

      context 'when the signing key cannot be loaded' do
        before do
          allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk)
            .and_raise(RuntimeError, 'Cloud Connector: no key found')
        end

        it 'tracks the exception and raises ConfigurationError rather than a bare 500', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(RuntimeError), hash_including(artifact_registry_token_mint: true, user_id: user.id))

          expect { token_exchange.token_for(user, organization) }
            .to raise_error(::ArtifactRegistry::Client::ConfigurationError, /could not be minted/)
        end
      end
    end

    # Membership is what makes the addressed organization safe to sign: without
    # it the token would name an organization the caller holds no role in.
    context 'when the caller is not a member of the addressed organization' do
      # A separate user: User#member_of_organization? memoizes per organization
      # on the instance, and let_it_be shares the instance across examples.
      let_it_be(:outsider) { create(:user) }

      it 'returns no credential and mints nothing', :aggregate_failures do
        expect(::Authn::TokenExchange::TokenIssuer).not_to receive(:new)

        expect(token_exchange.token_for(outsider, organization)).to be_nil
      end
    end

    context 'when no organization is addressed' do
      it 'returns no credential' do
        expect(token_exchange.token_for(user, nil)).to be_nil
      end
    end

    context 'when the principal is nil' do
      it 'returns no credential' do
        expect(token_exchange.token_for(nil, organization)).to be_nil
      end
    end

    context 'when the principal is not a User' do
      it 'returns no credential' do
        expect(token_exchange.token_for(Object.new, organization)).to be_nil
      end
    end
  end

  def decode(token)
    JWT.decode(token, cloud_connector_key.public_key, true, algorithm: 'RS256').first
  end
end
