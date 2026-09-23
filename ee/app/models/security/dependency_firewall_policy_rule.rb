# frozen_string_literal: true

module Security
  class DependencyFirewallPolicyRule < ApplicationRecord
    include PolicyRule

    self.table_name = 'dependency_firewall_policy_rules'

    # 3 is left unassigned for the in-flight `age` rule type (already in the policy schemas
    # but not yet here): https://gitlab.com/gitlab-org/gitlab/-/work_items/592789
    enum :type, { license: 0, vulnerability: 1, malicious: 2, risk_severity: 4 }, prefix: true

    belongs_to :security_policy, class_name: 'Security::Policy', inverse_of: :dependency_firewall_policy_rules,
      optional: false

    validates :typed_content,
      json_schema: { filename: "dependency_firewall_policy_rule_content", size_limit: 64.kilobytes }

    validates :type, presence: true

    validates :rule_index, presence: true
  end
end
