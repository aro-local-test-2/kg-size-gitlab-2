# frozen_string_literal: true

# Seeds the prevented-packages ledger so migrations touching the table are exercised by
# db:migrate:multi-version-upgrade. Inserts through a bare relation rather than
# Security::DependencyFirewallPreventedPackage, which lands in the chained model MR; the
# rule type and severity integers still come from their existing enums so this file is not
# a second place encoding them.
Gitlab::Seeder.quiet do
  ledger = Class.new(ApplicationRecord) do
    self.table_name = 'dependency_firewall_prevented_packages'
  end

  rule_types = ::Security::DependencyFirewallPolicyRule.types
  severities = ::Enums::Vulnerability.severity_levels

  packages = [
    { rule_type: 'license', identifier: 'pkg:npm/left-pad@1.3.0', severity: nil },
    { rule_type: 'malicious', identifier: 'pkg:npm/event-stream@3.3.6', severity: nil },
    { rule_type: 'vulnerability', identifier: 'pkg:npm/lodash@4.17.20', severity: 'high' },
    { rule_type: 'risk_severity', identifier: 'pkg:npm/minimist@0.0.8', severity: 'critical' }
  ]

  Project.limit(5).each do |project|
    now = Time.current

    rows = packages.map do |package|
      blocked_at = rand(1..72).hours.ago

      {
        project_id: project.id,
        rule_type: rule_types.fetch(package[:rule_type]),
        identifier: package[:identifier],
        first_seen_at: blocked_at,
        last_blocked_at: blocked_at,
        # Anchored to blocked_at so a warn never predates the package being first seen.
        last_warned_at: rand < 0.5 ? blocked_at + rand(1..12).hours : nil,
        severity: severities[package[:severity]],
        created_at: now,
        updated_at: now
      }
    end

    ledger.insert_all(rows, unique_by: 'i_dep_fw_prevented_packages_unique')
    print '.'
  end
end
