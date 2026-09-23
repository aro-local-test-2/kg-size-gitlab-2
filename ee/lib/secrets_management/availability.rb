# frozen_string_literal: true

module SecretsManagement
  class Availability
    LICENSED_FEATURE = :native_secrets_management

    class << self
      def for_project?(project)
        licensed?(project) && enabled_for_project?(project)
      end

      def for_group?(group)
        licensed?(group) && enabled_for_group?(group)
      end

      def for_instance?
        ::License.feature_available?(LICENSED_FEATURE) && InstanceEnrollment.enrolled?
      end

      def enabled_for_project?(project)
        ::Feature.enabled?(:secrets_manager, project) && enrolled?(project)
      end

      def enabled_for_group?(group)
        return false unless ::Feature.enabled?(:group_secrets_manager, group)

        # The paid experience grants SaaS top-level groups access before they enroll
        # so the trial CTA stays reachable. An explicit opt-out has to win over that
        # grant, otherwise turning the settings toggle off has no effect.
        return !opted_out?(group) if paid_experience_root_group?(group)

        enrolled?(group)
      end

      private

      def licensed?(resource)
        resource.licensed_feature_available?(LICENSED_FEATURE)
      end

      # The paid experience is SaaS-only (CustomersDot-driven); without this guard
      # an unenrolled self-managed instance would keep the implicit grant while
      # billing treats it as opted out.
      def paid_experience_root_group?(group)
        return false unless ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)

        group.root? && ::Feature.enabled?(:secrets_manager_paid_experience, group)
      end

      # rubocop:disable Gitlab/AvoidGitlabInstanceChecks -- routing between SaaS and self-managed enrollment
      def enrolled?(resource)
        if ::Gitlab.com?
          NamespaceEnrollment.enrolled?(resource)
        else
          InstanceEnrollment.enrolled?
        end
      end
      # rubocop:enable Gitlab/AvoidGitlabInstanceChecks

      # Only reached for paid-experience root groups, which are SaaS-only, so
      # the namespace enrollment record is the sole opt-out source here.
      def opted_out?(group)
        NamespaceEnrollment.opted_out?(group)
      end
    end
  end
end
