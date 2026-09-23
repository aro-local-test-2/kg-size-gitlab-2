# frozen_string_literal: true

module GitlabSubscriptions
  module AccessTokens
    class GroupPremiumOfferComponent < ViewComponent::Base
      include ::SafeFormatHelper

      UPGRADE_EVENT = 'click_upgrade_to_premium_on_group_access_tokens'
      EXPLORE_EVENT = 'click_explore_plans_on_group_access_tokens'
      LEARN_MORE_EVENT = 'click_learn_more_on_group_access_tokens'
      UPGRADE_CARD_TRACKING_SOURCE = 'group-access-tokens-upgrade-card'

      def initialize(group:)
        @group = group
      end

      private

      attr_reader :group

      def upgrade_to_premium_url
        premium_plan = plans_data&.find { |plan| plan.code == ::Plan::PREMIUM }

        ::GitlabSubscriptions::PurchaseUrlBuilder
          .new(plan_id: premium_plan&.id, namespace: root_ancestor)
          .build(source: UPGRADE_CARD_TRACKING_SOURCE)
      end

      def explore_plans_url
        helpers.group_billings_path(root_ancestor, source: UPGRADE_CARD_TRACKING_SOURCE)
      end

      def body_text
        link = helpers.link_to('', docs_url,
          target: '_blank', rel: 'noopener noreferrer',
          data: { event_tracking: LEARN_MORE_EVENT })

        safe_format(
          s_('AccessTokens|%{link_start}Group access token%{link_end} creation is not available ' \
            'on GitLab Free. Upgrade to Premium to create tokens scoped to this group and its projects.'),
          tag_pair(link, :link_start, :link_end)
        )
      end

      def docs_url
        helpers.help_page_path('user/group/settings/group_access_tokens.md')
      end

      def plans_data
        GitlabSubscriptions::FetchSubscriptionPlansService
          .new(plan: root_ancestor.plan_name_for_upgrading, namespace_id: root_ancestor.id)
          .execute
      end

      def root_ancestor
        @root_ancestor ||= group.root_ancestor
      end
    end
  end
end
