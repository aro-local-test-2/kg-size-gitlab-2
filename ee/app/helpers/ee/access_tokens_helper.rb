# frozen_string_literal: true

module EE
  module AccessTokensHelper
    extend ::Gitlab::Utils::Override

    UPGRADE_CARD_TRACKING_SOURCE = 'project-access-tokens-upgrade-card'

    override :personal_access_token_data
    def personal_access_token_data(token, user = current_user)
      super.deep_merge(
        access_token: {
          agentic_available: user.foundational_agent_available?('duo_permissions_assistant').to_s
        }
      )
    end

    override :show_group_access_tokens_premium_offer?
    def show_group_access_tokens_premium_offer?(group)
      return false if can?(current_user, :create_resource_access_tokens, group)
      return false unless ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
      return false unless can?(current_user, :read_billing, group.root_ancestor)

      group.root_ancestor.plan_name_for_upgrading == ::Plan::FREE
    end

    override :show_project_access_token_upgrade_card?
    def show_project_access_token_upgrade_card?(project)
      return false unless ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
      return false unless project.group
      return false if project.root_ancestor.licensed_feature_available?(:resource_access_token)
      return false if can?(current_user, :create_resource_access_tokens, project)

      can?(current_user, :read_billing, project.root_ancestor)
    end

    def project_access_token_upgrade_card_data(project)
      root = project.root_ancestor

      {
        docs_url: help_page_path('user/project/settings/project_access_tokens.md'),
        upgrade_url: project_access_token_premium_purchase_url(root),
        explore_plans_url: group_billings_path(root, source: UPGRADE_CARD_TRACKING_SOURCE)
      }
    end

    private

    def project_access_token_premium_purchase_url(namespace)
      plans_data = ::GitlabSubscriptions::FetchSubscriptionPlansService.new(
        plan: namespace.plan_name_for_upgrading,
        namespace_id: namespace.id
      ).execute
      premium_plan = plans_data&.find { |plan| plan.code == ::Plan::PREMIUM }

      ::GitlabSubscriptions::PurchaseUrlBuilder
        .new(plan_id: premium_plan&.id, namespace: namespace)
        .build(source: UPGRADE_CARD_TRACKING_SOURCE)
    end

    override :max_date_allowed
    def max_date_allowed
      return super unless personal_access_token_expiration_policy_enabled?

      personal_access_token_max_expiry_date&.iso8601
    end

    override :max_expiration_days
    def max_expiration_days
      return super unless personal_access_token_expiration_policy_enabled?

      personal_access_token_max_expiry_days
    end
  end
end
