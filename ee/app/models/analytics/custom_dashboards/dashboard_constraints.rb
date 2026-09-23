# frozen_string_literal: true

module Analytics
  module CustomDashboards
    # Constraints a dashboard must satisfy before it is shown, declared per
    # dashboard under the `constraints` key in its YAML.
    #
    # Each kind is a separate key rather than one list of tokens, so that the
    # JSON schema can validate each on its own terms, and so a caller can tell
    # a missing licence apart from a disabled feature flag -- those want
    # different treatment, an upsell versus hiding the dashboard entirely.
    class DashboardConstraints
      DATA_CHECKS = {
        'clickhouse' => -> { ::Gitlab::ClickHouse.globally_enabled_for_analytics? }
      }.freeze

      # The flag name has to appear as a literal symbol for the feature flag
      # tooling and the Gitlab/FeatureFlagKeyDynamic cop to find it, so a
      # dashboard names a token here rather than the flag itself.
      FEATURE_FLAG_CHECKS = {
        'dap_impact_v1' => ->(user) { ::Feature.enabled?(:dap_impact_v1, user) }
      }.freeze

      def self.satisfied?(dashboard, user)
        new(dashboard, user).satisfied?
      end

      def initialize(dashboard, user)
        @constraints = dashboard.constraints
        @user = user
      end

      def satisfied?
        licensed? && feature_flag_enabled? && data_available?
      end

      private

      attr_reader :constraints, :user

      # Instance-level is right for an organization-scoped dashboard, but it does not
      # discriminate on GitLab.com, where the licence maps to Ultimate for everyone.
      # See https://gitlab.com/gitlab-org/gitlab/-/work_items/630026
      def licensed?
        name = constraints['license']
        return true unless name

        ::License.feature_available?(name.to_sym)
      end

      # These flags are user-actored, which is why the policy condition calling
      # this cannot use `scope: :subject` -- that caches one user's answer for
      # everyone.
      def feature_flag_enabled?
        token = constraints['feature_flag']
        return true unless token

        FEATURE_FLAG_CHECKS.fetch(token).call(user)
      end

      def data_available?
        Array(constraints['data']).all? { |name| DATA_CHECKS.fetch(name).call }
      end
    end
  end
end
