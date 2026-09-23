# frozen_string_literal: true

module EE
  module Gitlab
    module BillingEvents
      module Client
        extend ::Gitlab::Utils::Override

        INSTANCE_UID_CLAIM = 'gitlab_instance_uid'
        INSTANCE_UID_CACHE_KEY = 'billing_events:cloud_connector_instance_uid'
        # The Cloud Connector token is synced daily and valid for days; the uid it carries
        # only changes when the instance is re-activated, so a short process-local cache
        # avoids a database read and a token decrypt per billing event.
        INSTANCE_UID_CACHE_TTL = 1.hour

        # Air-gapped instances are licensed offline and have no route to the billing
        # collector. A connected instance running an offline licence also qualifies,
        # which is harmless: it gains a local record and an export path it would
        # otherwise not have.
        #
        # The realm guard is belt and braces. GitLab.com is not provisioned from an
        # offline subscription, so the licence check alone should exclude it, but that
        # rests on CustomersDot data rather than on anything readable here. The realm
        # comes from `Gitlab.org_or_com?`, so this makes the exclusion structural and
        # keeps `billable_usage_daily_aggregates` unwritable on .com and on Cells.
        override :local_persistence_enabled?
        def local_persistence_enabled?
          return super unless ::Feature.enabled?(:local_billing_persistence, :instance)
          return super if ::CloudConnector.gitlab_realm_saas?

          !!::License.current&.offline_cloud_license?
        end

        private

        override :realm
        def realm
          raw = ::CloudConnector.gitlab_realm
          ::Gitlab::BillingEvents::Client::REALM_MAP.fetch(raw)
        end

        override :deployment_type
        def deployment_type
          ::CloudConnector.deployment_type
        end

        override :unique_instance_id
        def unique_instance_id
          return super if ::CloudConnector.gitlab_realm == ::CloudConnector::GITLAB_REALM_SAAS

          cloud_connector_instance_uid || super
        end

        def cloud_connector_instance_uid
          ::Gitlab::ProcessMemoryCache.cache_backend.fetch(
            INSTANCE_UID_CACHE_KEY, expires_in: INSTANCE_UID_CACHE_TTL, skip_nil: true
          ) do
            read_cloud_connector_instance_uid
          end
        end

        def read_cloud_connector_instance_uid
          token = ::CloudConnector::Tokens.cloud_connector_token
          return unless token

          # Decoded without signature verification: only the claim is read here; the
          # collector is the party that verifies the token.
          payload, _header = JWT.decode(token, nil, false)
          payload[INSTANCE_UID_CLAIM].presence
        rescue StandardError => e
          ::Gitlab::ErrorTracking.track_exception(
            e,
            message: 'BillingEvents: could not read the instance uid from the Cloud Connector token'
          )
          nil
        end

        def persist_local_aggregate(context, quantity_kind)
          ::Utilization::BillableUsage::RecordAggregateService
            .new(context, quantity_kind: quantity_kind)
            .execute
        end
      end
    end
  end
end
