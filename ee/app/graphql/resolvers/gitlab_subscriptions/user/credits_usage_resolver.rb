# frozen_string_literal: true

module Resolvers
  module GitlabSubscriptions
    module User
      class CreditsUsageResolver < BaseResolver
        type ::Types::GitlabSubscriptions::User::CreditsUsageType, null: true

        authorizes_object!
        authorize :read_user

        argument :namespace_path, GraphQL::Types::ID,
          required: true,
          description: 'Path of the top-level namespace to report usage for.'

        argument :start_date, GraphQL::Types::ISO8601Date,
          required: false,
          description: 'Start date of the usage period to query. Defaults to the beginning of the current month.'

        argument :end_date, GraphQL::Types::ISO8601Date,
          required: false,
          description: 'End date of the usage period to query. Defaults to the end of the current month.'

        argument :flow_types, [GraphQL::Types::String],
          required: false,
          description: 'Filter usage data by flow type identifiers (for example, ["chat", "code_review"]).'

        MAX_DATE_RANGE = 1.year

        def resolve(**args)
          start_date = args[:start_date] || Date.current.beginning_of_month
          end_date = args[:end_date] || Date.current.end_of_month

          validate_date_range!(start_date, end_date)

          namespace = find_namespace(args[:namespace_path])

          authorize!(namespace)

          effective_start = clamp_start_date(start_date, namespace)
          effective_end = [end_date, Date.current].min

          subscription_usage_client = ::Gitlab::SubscriptionPortal::SubscriptionUsageClient.new(
            namespace_id: namespace.id,
            start_date: effective_start.iso8601,
            end_date: effective_end.iso8601
          )

          ::GitlabSubscriptions::SubscriptionsUsage::User::CreditsUsage.new(
            user: object,
            namespace: namespace,
            subscription_usage_client: subscription_usage_client,
            flow_types: args[:flow_types].presence
          )
        end

        private

        def authorize!(namespace)
          raise_resource_not_available_error! unless ::Feature.enabled?(:user_gitlab_credits_dashboard, namespace)
          raise_resource_not_available_error! unless object == current_user
          raise_resource_not_available_error! unless current_user.human?
          raise_resource_not_available_error! unless namespace
          raise_resource_not_available_error! unless namespace.root? && namespace.group_namespace?
          raise_resource_not_available_error! unless namespace.gitlab_credits_entitled?
          raise_resource_not_available_error! unless namespace.member_of_self_or_descendant?(current_user)
        end

        def validate_date_range!(start_date, end_date)
          if end_date < start_date
            raise Gitlab::Graphql::Errors::ArgumentError,
              "end_date must be after or equal to start_date"
          end

          return unless end_date > start_date + MAX_DATE_RANGE

          raise Gitlab::Graphql::Errors::ArgumentError,
            "Date range cannot exceed 1 year"
        end

        def find_namespace(namespace_path)
          Namespace.find_by_full_path(namespace_path)
        end

        def clamp_start_date(start_date, namespace)
          subscription_start = namespace.gitlab_subscription&.start_date

          return start_date unless subscription_start

          [start_date, subscription_start].max
        end
      end
    end
  end
end
