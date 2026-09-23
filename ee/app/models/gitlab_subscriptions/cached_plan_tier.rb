# frozen_string_literal: true

module GitlabSubscriptions
  module CachedPlanTier
    FREE = ::Plan::FREE

    CACHE_EXPIRATION = 10.minutes

    # Bounds the expiry stampede. A single hot requester or namespace can be behind
    # hundreds of concurrent requests, and fetch_once takes no lock, so without this
    # every one of them would miss together and run the same query.
    RACE_CONDITION_TTL = 10.seconds

    class << self
      # GitLab.com only: self-managed has no per-namespace subscription rows, so every
      # id resolves to FREE there.
      def for_user_id(user_id)
        return FREE unless user_id

        fetch_tier(user_cache_key(user_id)) do
          highest_tier(plan_name_uids_for_user(user_id))
        end
      end

      def for_root_namespace_id(root_namespace_id)
        return FREE unless root_namespace_id

        fetch_tier(namespace_cache_key(root_namespace_id)) do
          tier_for_uid(hosted_plan_name_uid(root_namespace_id))
        end
      end

      private

      def fetch_tier(key, &block)
        ::Gitlab::Cache.fetch_once(
          key, expires_in: CACHE_EXPIRATION, race_condition_ttl: RACE_CONDITION_TTL, &block
        )
      end

      def user_cache_key(user_id)
        "plan_tier:user:#{user_id}"
      end

      def namespace_cache_key(root_namespace_id)
        "plan_tier:namespace:#{root_namespace_id}"
      end

      # Don't remove this FREE default. The query can return zero rows: a user with
      # no memberships and no provisioning data matches nothing, so there is no plan
      # to read. FREE is the fallback for that case.
      def highest_tier(plan_name_uids)
        names = ::GitlabSubscriptions::SystemDefined::Plan.names_for_uids(plan_name_uids.compact)

        names.map { |name| ::Plan.tier_for(name) }.max_by { |tier| ::Plan::TIERS.index(tier) } || FREE
      end

      # A namespace with no subscription row, or one carrying no plan name uid, has
      # no plan to read.
      def tier_for_uid(plan_name_uid)
        name = ::GitlabSubscriptions::SystemDefined::Plan.names_for_uids([plan_name_uid].compact).first
        return FREE unless name

        ::Plan.tier_for(name)
      end

      # One DB round trip; unique index on namespace_id, nil if no subscription row
      def hosted_plan_name_uid(root_namespace_id)
        ::GitlabSubscription.where(namespace_id: root_namespace_id).pick(:hosted_plan_name_uid)
      end

      # Single round trip; subquery inlined, returns up to 12 distinct plan uids
      def plan_name_uids_for_user(user_id)
        candidates = ::Namespace
          .from("(#{candidate_root_ids(user_id)}) #{::Namespace.table_name}")
          .select(:id)

        ::GitlabSubscription
          .where(namespace_id: candidates)
          .where.not(hosted_plan_name_uid: nil)
          .distinct
          .limit(::GitlabSubscriptions::SystemDefined::Plan::ITEMS.size)
          .pluck(:hosted_plan_name_uid)
      end

      # No query executes; returns SQL text embedded as subquery, UNION ALL (no dedup)
      def candidate_root_ids(user_id)
        ::Gitlab::SQL::Union.new([
          ::Member.without_invites_and_requests.where(user_id: user_id)
                  .joins(:member_namespace).select(root_id_column),
          ::Namespace.where(id: provisioned_group_id(user_id)).select(root_id_column),
          ::Namespace.where(id: provisioned_project_namespace_id(user_id)).select(root_id_column)
        ], remove_duplicates: false).to_sql
      end

      def root_id_column
        Arel.sql("#{::Namespace.table_name}.traversal_ids[1] AS id")
      end

      # Group id is already a namespace id; may be a subgroup, hence caller's root fold
      def provisioned_group_id(user_id)
        ::UserDetail.where(user_id: user_id).select(:provisioned_by_group_id)
      end

      # Translates project id to projects.namespace_id, which caller folds to root
      def provisioned_project_namespace_id(user_id)
        ::UserDetail
          .where(user_id: user_id)
          .joins(:provisioned_by_project)
          .select("#{::Project.table_name}.namespace_id")
      end
    end
  end
end
