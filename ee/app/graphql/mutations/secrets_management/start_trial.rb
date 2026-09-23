# frozen_string_literal: true

module Mutations
  module SecretsManagement
    class StartTrial < BaseMutation
      graphql_name 'SecretsManagerStartTrial'

      include Mutations::ResolvesGroup
      include Gitlab::InternalEventsTracking

      # Shares the enrollment gate (SaaS, top-level, licensed, namespace enrollment
      # flag): the trial flow enrolls first, so both mutations must open together.
      # Self-managed is instance-wide and admin-only: SecretsManagerInstanceStartTrial.
      authorize :start_secrets_manager_trial

      # The payload's EntitlementType requires read_secrets_manager, so a token
      # without it would get a silent null entitlement after a successful start.
      authorize_granular_token permissions: [:start_secrets_manager_trial, :read_secrets_manager],
        boundary_argument: :group_path,
        boundary_type: :group

      argument :group_path,
        GraphQL::Types::ID,
        required: true,
        description: 'Full path of the top-level group to start a Secrets Manager trial for.'

      field :entitlement,
        ::Types::SecretsManagement::EntitlementType,
        null: true,
        description: 'Secrets Manager entitlement state after starting the trial. ' \
          'Null when the post-trial state cannot be resolved; query the group entitlement directly instead.'

      UNAVAILABLE_ERROR = 'Unable to reach the subscription service. Please try again later.'

      ERROR_MESSAGES = {
        trial_already_active: 'A Secrets Manager trial is already active for this group.',
        ineligible: 'This group is not eligible to start a Secrets Manager trial.',
        not_found: 'This group is not recognized by the subscription service.'
      }.freeze

      def resolve(group_path:)
        group = authorized_find!(group_path: group_path)

        raise_resource_not_available_error! unless ::Feature.enabled?(:secrets_manager_paid_experience, group)

        result = ::Gitlab::SubscriptionPortal::Client.start_secrets_manager_trial(namespace_id: group.id)

        if result.success?
          # The pre-trial answers are still cached, and a blocked resolve would
          # otherwise outlive the trial for the rest of its TTL. The resolver's
          # layers go too, or the last-known-good slot lets a transport failure
          # on the lookup below replay the pre-trial answer.
          ::Gitlab::SubscriptionPortal::Client.expire_secrets_manager_cache(namespace_id: group.id)
          ::SecretsManagement::Entitlement::Resolver.clear_cache(group)

          track_internal_event('secrets_manager_trial_started', namespace: group, user: current_user)

          # Trial is already started on CDot; a post-trial lookup failure must not fail the mutation.
          { entitlement: resolve_entitlement(group), errors: [] }
        else
          failure_response(group, failure_reason_for(result), error_message_for(result))
        end
      rescue ::Gitlab::SubscriptionPortal::SecretsManagerStartTrialResponse::Error => e
        ::Gitlab::ErrorTracking.track_exception(e, gl_namespace_id: group.id)

        failure_response(group, :unavailable)
      end

      private

      def find_object(group_path:)
        resolve_group(full_path: group_path)
      end

      def error_response(message)
        { entitlement: nil, errors: [message] }
      end

      def failure_response(group, reason, message = nil)
        track_internal_event(
          'secrets_manager_trial_start_failed',
          namespace: group,
          user: current_user,
          additional_properties: { label: reason.to_s }
        )

        error_response(message || UNAVAILABLE_ERROR)
      end

      def failure_reason_for(result)
        ERROR_MESSAGES.key?(result.error_code) ? result.error_code : :unavailable
      end

      def error_message_for(result)
        return result.error_message if result.error_code == :ineligible && result.error_message.present?

        ERROR_MESSAGES.fetch(result.error_code, UNAVAILABLE_ERROR)
      end

      def resolve_entitlement(group)
        entitlement_for(group)
      rescue StandardError => e
        ::Gitlab::ErrorTracking.track_exception(e, gl_namespace_id: group.id)

        nil
      end

      # `for!` because `for` fails closed to `:ineligible` inside the resolver:
      # the rescue in `resolve_entitlement` needs the failure to propagate, and
      # the field is documented as null when the state cannot be resolved.
      def entitlement_for(group)
        entitlement = ::SecretsManagement::Entitlement.for!(group, user: current_user)
        ::Types::SecretsManagement::EntitlementType::Adapter.new(entitlement: entitlement, group: group)
      end
    end
  end
end
