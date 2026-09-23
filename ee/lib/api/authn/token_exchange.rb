# frozen_string_literal: true

module API
  module Authn
    # PoC token-exchange endpoint for modular services. Marked experimental --
    # the surface is expected to be superseded by GATE L2 later
    # (ADR-016 / ADR-019).
    class TokenExchange < ::API::Base
      include APIGuard

      feature_category :system_access

      # Audiences this endpoint may mint tokens for. Modular services join
      # by adding their `jwt_aud` here.
      SUPPORTED_AUDIENCES = %w[gitlab-artifact-registry].freeze

      MAX_EXPIRES_IN_SECONDS = 12.hours.to_i

      before do
        authenticate!
      end

      namespace 'token_exchange' do
        desc 'Issue a short-lived JWT for a single modular-service audience' do
          detail 'Issues a short-lived RS256 JWT scoped to one modular-service audience ' \
            '(such as the Artifact Registry). Claims include the requesting user (sub) and the ' \
            'organization it acts in. When called with a CI job token, the claims also carry ' \
            'the job project id and commit SHA as build provenance. Presented to the ' \
            'corresponding backend and verified against the instance JWKS.'
          success code: 201
          failure [
            { code: 400, message: 'Bad Request' },
            { code: 401, message: 'Unauthorized' },
            { code: 403, message: 'Forbidden' }
          ]
          tags %w[token_exchange]
        end
        route_setting :lifecycle, :experiment
        # Internal-only endpoint -- not exposed via the granular PAT system.
        # All existing PATs (legacy or granular) can call this endpoint without
        # needing to opt into a per-endpoint permission.
        # skip_job_token_policies: this endpoint does not act on a project
        # resource (no read_*/admin_* policy from ci_job_token_policies.json fits).
        # The job token is only the auth credential; the token we mint is
        # scoped via `audience`.
        route_setting :authorization,
          skip_granular_token_authorization: :modular_service_token_exchange,
          skip_job_token_policies: true
        # AR auth interface agreement R1: must accept CI job tokens.
        # The endpoint is not project-scoped, so any job token authenticates as
        # job.user (whoever ran that build, human or bot), not a per-build bot.
        #
        # Deploy tokens are deliberately NOT enabled here: DeployToken is not a
        # User, so our User-shaped payload (sub, gitlab_organization_id) doesn't
        # apply. R1 lists deploy tokens but R3 ("the principal's GitLab ID") has
        # no defined shape for non-User callers. Tracked as a follow-up.
        route_setting :authentication, job_token_allowed: true
        params do
          requires :audience, type: String,
            values: SUPPORTED_AUDIENCES,
            desc: 'Target service audience (e.g. gitlab-artifact-registry)'
          optional :expires_in, type: Integer,
            values: 1..MAX_EXPIRES_IN_SECONDS,
            default: ::Authn::TokenExchange::TokenIssuer::DEFAULT_TTL_SECONDS,
            desc: 'Requested token lifetime in seconds. ' \
              'The granted lifetime may be shorter than requested depending on the ' \
              'authentication method used to call this endpoint.'
        end
        helpers do
          # Expected to stay at zero under the closed beta. If it moves, the
          # single-organization assumption the resolver rests on is wrong.
          def ambiguous_organization_counter
            ::Gitlab::Metrics.counter(
              :token_exchange_ambiguous_organization_total,
              'Token exchange requests refused because the caller belongs to more than one ' \
                'Artifact Registry organization'
            )
          end

          # A job token must not mint a credential that outlives its job. Past
          # the deadline the runner has already killed the script, so refuse
          # rather than grant a window the caller could keep renewing.
          def job_token_ttl_ceiling!(job)
            deadline = job.started_at && job.timeout_value && (job.started_at + job.timeout_value.seconds)
            # Deadline unknown: the default, not the endpoint cap.
            return ::Authn::TokenExchange::TokenIssuer::DEFAULT_TTL_SECONDS unless deadline

            remaining = (deadline - Time.current).to_i
            forbidden!(_('The job that requested this token has exceeded its timeout.')) unless remaining > 0

            remaining
          end
        end

        post do
          check_rate_limit!(:token_exchange, scope: current_user)

          ttl = declared_params[:expires_in]
          ttl = [ttl, job_token_ttl_ceiling!(current_authenticated_job)].min if current_authenticated_job

          # Inferred from the caller's memberships rather than read off their
          # account, because a package client cannot say which organization it
          # means and the account's own organization is the wrong answer once a
          # group has moved into a promoted one.
          #
          # Not the X-GitLab-Organization-ID header either. Nothing verifies
          # it, and a membership check would not rescue it: package clients
          # cannot send that header at all, so the callers who need a
          # different organization are exactly the ones it cannot help.
          organization =
            begin
              ::Authn::TokenExchange::OrganizationResolver.new(current_user).execute
            rescue ::Authn::TokenExchange::OrganizationResolver::AmbiguousOrganizationError
              ambiguous_organization_counter.increment
              conflict!(_('Your account belongs to more than one organization with Artifact Registry. ' \
                'This is not supported yet.'))
            end

          # Every caller of this endpoint needs Relationships/Lookup API access,
          # so DATA_ACCESS_AUDIENCE is always included here (opt-in for other TokenIssuer callers).
          token = ::Authn::TokenExchange::TokenIssuer.new(
            audiences: [declared_params[:audience], ::Authn::TokenExchange::TokenIssuer::DATA_ACCESS_AUDIENCE],
            user: current_user,
            organization: organization,
            ttl: ttl,
            job: current_authenticated_job
          ).token

          # TODO (production): emit a `Gitlab::InternalEvents.track_event` for usage analytics
          # (event name e.g. `token_exchange_issued`, additional_properties carrying the
          # audience). Requires an event YAML in config/events/.

          present({ token: token }, with: Grape::Presenters::Presenter)
        end
      end
    end
  end
end
