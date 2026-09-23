# frozen_string_literal: true

module Security
  module DependencyFirewall
    class PolicyEvaluator
      include Gitlab::Utils::StrongMemoize

      def initialize(project, current_user)
        @project = project
        @current_user = current_user
      end

      # example PURL breakdown for maven/org.apache.xmlgraphics/batik-anim@1.9.1
      # name: org.apache.xmlgraphics/batik-anim
      # purl_type: maven
      # version: 1.9.1 (optional)
      def evaluate(name, purl_type:, version: nil, licenses: [], vulnerabilities: [], malicious_packages: [])
        return [] unless Availability.feature_flag_enabled?(project)

        return [no_policies_result] if policies.empty?

        evaluate_policies(
          { name: name, purl_type: purl_type, version: version },
          licenses,
          policies,
          vulnerabilities,
          malicious_packages
        )
      end

      private

      attr_reader :project, :current_user

      # Lets the caller distinguish an evaluation that happened from one that never could: with no
      # policy linked, no rule ran, so allowing is the absence of a verdict rather than a verdict.
      def no_policies_result
        build_result(::Security::DependencyFirewallPolicies::Rule::ACTION_ALLOWED,
          ::Security::DependencyFirewallPolicies::Rule::REASON_NO_POLICIES)
      end

      def evaluate_policies(package, licenses, policies, vulnerabilities, malicious_packages)
        metadata = {
          licenses: licenses,
          vulnerabilities: vulnerabilities,
          malicious_packages: malicious_packages
        }

        policies.map do |policy|
          evaluate_policy(policy, package, metadata).merge(policy_name: policy.name)
        end
      end

      def evaluate_policy(policy, package, metadata)
        bypass_settings = policy.bypass_settings
        allowed = ::Security::DependencyFirewallPolicies::Rule::ACTION_ALLOWED

        return build_result(allowed, :user_bypassed) if bypass_settings.user_bypassed?(@current_user)
        return build_result(allowed, :token_bypassed) if bypass_settings.access_token_bypassed?(@current_user)

        # Every rule soft-deleted leaves nothing to evaluate. Reporting REASON_NO_MATCHES here would
        # claim rules ran and matched nothing.
        if policy.rules.none?
          return build_result(allowed, ::Security::DependencyFirewallPolicies::Rule::REASON_NO_RULES)
        end

        policy_result(matching_rules(policy, package, metadata), policy.enforcement_type)
      end

      def matching_rules(policy, package, metadata)
        policy.rules.filter_map do |rule|
          rule.evaluate(package, metadata: metadata)&.merge(rule: rule)
        end
      end

      def policies
        return [] unless project

        project.security_policies
               .enabled
               .type_dependency_firewall_policy
               .preload(:undeleted_dependency_firewall_policy_rules) # rubocop: disable CodeReuse/ActiveRecord -- not an ActiveRecord model
               .map(&:dependency_firewall_policy)
      end
      strong_memoize_attr :policies

      def policy_result(matched_rules, enforcement_type)
        denied_rule = matched_rules.find { |rule| rule[:action] == ::Security::DependencyFirewallPolicies::Rule::ACTION_DENIED }

        if denied_rule
          # Default to 'enforced' (denied) if nil/missing for security
          if enforcement_type == 'warn'
            return build_result(
              ::Security::DependencyFirewallPolicies::Rule::ACTION_WARNED,
              ::Security::DependencyFirewallPolicies::Rule::REASON_EVALUATION,
              matched_rule: denied_rule[:rule],
              details: denied_rule[:details])
          end

          return build_result(
            ::Security::DependencyFirewallPolicies::Rule::ACTION_DENIED,
            ::Security::DependencyFirewallPolicies::Rule::REASON_EVALUATION,
            matched_rule: denied_rule[:rule],
            details: denied_rule[:details])
        end

        if matched_rules.empty?
          return build_result(
            ::Security::DependencyFirewallPolicies::Rule::ACTION_ALLOWED,
            ::Security::DependencyFirewallPolicies::Rule::REASON_NO_MATCHES)
        end

        all_rules_exceptions = matched_rules.all? do |rule|
          rule[:action] == ::Security::DependencyFirewallPolicies::Rule::ACTION_ALLOWED &&
            rule[:reason] == ::Security::DependencyFirewallPolicies::Rule::REASON_EXCEPTION
        end

        if all_rules_exceptions
          return build_result(
            ::Security::DependencyFirewallPolicies::Rule::ACTION_ALLOWED,
            ::Security::DependencyFirewallPolicies::Rule::REASON_EXCEPTION)
        end

        build_result(
          ::Security::DependencyFirewallPolicies::Rule::ACTION_ALLOWED,
          ::Security::DependencyFirewallPolicies::Rule::REASON_EVALUATION)
      end

      def build_result(action, reason, matched_rule: nil, details: nil)
        result = { action: action, reason: reason }
        result[:matched_rule] = matched_rule if matched_rule
        result[:details] = details if details
        result
      end
    end
  end
end
