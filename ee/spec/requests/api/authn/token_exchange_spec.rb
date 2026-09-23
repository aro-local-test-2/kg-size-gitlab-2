# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Authn::TokenExchange, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:pat) { create(:personal_access_token, user: user) }
  let_it_be(:second_user) { create(:user) }
  let_it_be(:second_pat) { create(:personal_access_token, user: second_user) }
  let_it_be(:cloud_connector_keys) { create(:cloud_connector_keys) }

  let(:url) { '/token_exchange' }
  let(:params) { { audience: 'gitlab-artifact-registry' } }

  describe 'POST /token_exchange' do
    # Verify with the loader's current key -- the exact key the issuer signed with.
    def token_claims
      public_key = ::CloudConnector::CachingKeyLoader.private_jwk.verify_key
      JWT.decode(json_response['token'], public_key, true, algorithm: 'RS256').first
    end

    context 'with a valid audience' do
      it 'returns a token for the authenticated user', :aggregate_failures do
        post(api(url, personal_access_token: pat), params: params)

        expect(response).to have_gitlab_http_status(:created)

        claims = token_claims
        expect(claims['aud']).to match_array(%w[gitlab-artifact-registry gitlab-iam-data-access])
        expect(claims['sub']).to eq(user.to_global_id.to_s)
        expect(claims['ver']).to eq(1)
        expect(claims['gitlab']).to include(
          'origin' => 'organization',
          'origin_id' => user.organization.uuid,
          'local_id' => user.id,
          'identity_kind' => 'user',
          'organization_role' => 'member'
        )

        %w[gitlab_realm gitlab_organization_id gitlab_organization_role].each do |removed|
          expect(claims).not_to have_key(removed)
        end
        expect(claims['gitlab']).not_to have_key('job')
      end

      # Current.organization is resolved from this header with no membership
      # check, so the token must not follow it. Otherwise a caller could mint a
      # signed token naming an organization they have no relationship with.
      it 'ignores X-GitLab-Organization-ID and stays on the caller organization', :aggregate_failures do
        other_organization = create(:organization)

        post(api(url, personal_access_token: pat), params: params,
          headers: { 'X-GitLab-Organization-ID' => other_organization.id.to_s })

        expect(response).to have_gitlab_http_status(:created)
        expect(token_claims['gitlab']['origin_id']).to eq(user.organization.uuid)
        expect(token_claims['gitlab']['origin_id']).not_to eq(other_organization.uuid)
      end

      context 'when the caller belongs to one Artifact Registry organization' do
        let_it_be(:ar_organization) { create(:organization) }

        before_all do
          create(:artifact_registry_namespace_mapping, organization: ar_organization)
          create(:organization_user, organization: ar_organization, user: user)
        end

        it 'mints for that organization rather than the one owning the account', :aggregate_failures do
          post(api(url, personal_access_token: pat), params: params)

          expect(response).to have_gitlab_http_status(:created)
          expect(token_claims['gitlab']['origin_id']).to eq(ar_organization.uuid)
          expect(token_claims['gitlab']['origin_id']).not_to eq(user.organization.uuid)
        end
      end

      context 'when the caller belongs to more than one Artifact Registry organization' do
        before do
          2.times do
            organization = create(:organization)
            create(:artifact_registry_namespace_mapping, organization: organization)
            create(:organization_user, organization: organization, user: user)
          end
        end

        it 'refuses rather than minting a guess', :aggregate_failures do
          post(api(url, personal_access_token: pat), params: params)

          expect(response).to have_gitlab_http_status(:conflict)
          expect(json_response['message']).to include('more than one organization')
        end
      end

      context 'with a granular personal access token' do
        let_it_be(:granular_pat) { create(:granular_pat, user: user) }

        it 'issues a token (skip_granular_token_authorization is honoured)' do
          post(api(url, personal_access_token: granular_pat), params: params)

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['token']).to be_present
        end
      end

      context 'with an OAuth access token' do
        let_it_be(:oauth_token) { create(:oauth_access_token, resource_owner: user, scopes: [:api]) }

        it 'issues a token' do
          post(api(url, oauth_access_token: oauth_token), params: params)

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['token']).to be_present
        end
      end

      context 'with a project access token' do
        let_it_be(:project) { create(:project) }
        let_it_be(:project_access_token) { create(:resource_access_token, resource: project) }

        it 'issues a token' do
          post(api(url, personal_access_token: project_access_token), params: params)

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['token']).to be_present
          expect(token_claims['sub']).to eq(project_access_token.user.to_global_id.to_s)
        end
      end

      context 'with a CI job token' do
        let_it_be(:project) { create(:project) }
        # The :running trait sets no timeout, so this build takes the
        # unknown-deadline path. Set started_at/timeout explicitly to exercise
        # the clamp.
        let_it_be(:ci_build) { create(:ci_build, :running, project: project, user: user) }

        it 'issues a token (job_token_allowed route_setting is honoured)' do
          post(api(url), params: params.merge(job_token: ci_build.token))

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['token']).to be_present
        end

        it 'carries the job project and commit as build provenance', :aggregate_failures do
          post(api(url), params: params.merge(job_token: ci_build.token))

          expect(response).to have_gitlab_http_status(:created)

          claims = token_claims
          expect(claims['gitlab']['job']).to eq(
            'project_id' => project.id,
            'git_commit_sha' => ci_build.sha
          )
          expect(claims['sub']).to eq(user.to_global_id.to_s)
        end

        # The credential a job mints must not outlive the job that asked for it.
        # These use `let`, not `let_it_be`: `let_it_be` runs before the
        # `freeze_time` hook, so the relative timestamps would drift.
        context 'when the job deadline is known', :freeze_time, :aggregate_failures do
          let(:job) do
            create(:ci_build, :running, project: project, user: user,
              started_at: 10.minutes.ago, timeout: 1.hour.to_i)
          end

          it 'clamps a request that exceeds the remaining job time' do
            post(api(url), params: params.merge(job_token: job.token, expires_in: 12.hours.to_i))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(50.minutes.to_i)
          end

          it 'honours a request shorter than the remaining job time' do
            post(api(url), params: params.merge(job_token: job.token, expires_in: 60))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(60)
          end

          it 'is a no-op when the request equals the remaining job time' do
            post(api(url), params: params.merge(job_token: job.token, expires_in: 50.minutes.to_i))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(50.minutes.to_i)
          end
        end

        # The clamp has to bite below the default ttl, not only above it.
        context 'when less than the default ttl remains', :freeze_time, :aggregate_failures do
          let(:job) do
            create(:ci_build, :running, project: project, user: user,
              started_at: 59.minutes.ago, timeout: 1.hour.to_i)
          end

          it 'clamps an explicit request down to the remaining job time' do
            post(api(url), params: params.merge(job_token: job.token, expires_in: 12.hours.to_i))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(60)
          end

          it 'clamps the default ttl down to the remaining job time' do
            post(api(url), params: params.merge(job_token: job.token))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(60)
          end
        end

        context 'when the job deadline is unknown', :aggregate_failures do
          it 'falls back to the default ttl when the timeout is unset' do
            job = create(:ci_build, :running, project: project, user: user, timeout: nil)

            post(api(url), params: params.merge(job_token: job.token, expires_in: 12.hours.to_i))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(300)
          end

          it 'falls back to the default ttl when started_at is unset' do
            job = create(:ci_build, :running, project: project, user: user,
              started_at: nil, timeout: 1.hour.to_i)

            post(api(url), params: params.merge(job_token: job.token, expires_in: 12.hours.to_i))

            expect(response).to have_gitlab_http_status(:created)
            expect(token_claims['exp'] - token_claims['iat']).to eq(300)
          end
        end

        context 'when the job deadline has already passed', :freeze_time do
          it 'refuses the exchange' do
            job = create(:ci_build, :running, project: project, user: user,
              started_at: 3.hours.ago, timeout: 1.hour.to_i)

            post(api(url), params: params.merge(job_token: job.token, expires_in: 12.hours.to_i))

            expect(response).to have_gitlab_http_status(:forbidden)
          end

          it 'refuses the exchange at exactly the deadline' do
            job = create(:ci_build, :running, project: project, user: user,
              started_at: 1.hour.ago, timeout: 1.hour.to_i)

            post(api(url), params: params.merge(job_token: job.token))

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end
      end

      context 'with no expires_in' do
        it 'defaults to a 300 second ttl' do
          post(api(url, personal_access_token: pat), params: params)

          claims = token_claims
          expect(claims['exp'] - claims['iat']).to eq(300)
        end
      end

      context 'with expires_in within range' do
        it 'applies the requested expires_in' do
          post(api(url, personal_access_token: pat), params: params.merge(expires_in: 600))

          claims = token_claims
          expect(claims['exp'] - claims['iat']).to eq(600)
        end
      end

      context 'with expires_in at the upper bound' do
        it 'is not clamped for a caller that is not a job' do
          post(api(url, personal_access_token: pat), params: params.merge(expires_in: 12.hours.to_i))

          claims = token_claims
          expect(claims['exp'] - claims['iat']).to eq(12.hours.to_i)
        end
      end

      context 'with expires_in above the upper bound' do
        it 'returns 400' do
          post(api(url, personal_access_token: pat), params: params.merge(expires_in: 13.hours.to_i))

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :token_exchange do
      let(:current_user) { user }

      def request
        post(api(url, personal_access_token: pat), params: params)
      end

      def request_with_second_scope
        post(api(url, personal_access_token: second_pat), params: params)
      end
    end

    context 'with an unknown audience' do
      it 'returns 400' do
        post(api(url, personal_access_token: pat), params: { audience: 'unknown' })

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'without authentication' do
      it 'returns 401' do
        post(api(url), params: params)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'with a deploy token' do
      let_it_be(:deploy_token) { create(:deploy_token) }

      it 'returns 401 (deploy_token_allowed is intentionally not set)' do
        post(
          api(url),
          params: params,
          headers: { Gitlab::Auth::AuthFinders::DEPLOY_TOKEN_HEADER => deploy_token.token }
        )

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end
  end
end
