# frozen_string_literal: true

module Security
  module DependencyFirewallPolicies
    class RiskSeverityRule < Rule
      # Report order for exceeded severities, so the violation message is deterministic rather
      # than dependent on the order the policy author happened to list them in.
      SEVERITY_ORDER = %w[critical high medium low].freeze

      # Shared by the pipeline violation message and the audit message, so both surfaces describe
      # the same event identically.
      def self.format_exceeded(exceeded)
        exceeded.map { |entry| "#{entry[:severity]}: #{entry[:count]} of #{entry[:threshold]}" }.join(', ')
      end

      # Tallies vulnerabilities by severity and reports the policy entries whose threshold the
      # tally exceeds.
      class SeverityTally
        def initialize(vulnerabilities)
          # Dedupe by identifier first. The fetch service emits one entry per affected-package row,
          # and rows differing only by distro_version share an advisory, so one CVE can arrive twice.
          @counts = vulnerabilities.uniq { |vuln| vuln[:id] }.each_with_object(Hash.new(0)) do |vuln, counts|
            counts[vuln[:severity]] += 1
          end
        end

        # A severity is evaluated only when the policy lists it. Because the schema restricts
        # `severity` to critical/high/medium/low, severities the fetch service can produce but a
        # policy cannot name -- 'unknown' and 'none' -- are never looked up and never tally.
        def exceeded(denied_entries)
          denied_entries
            .sort_by { |entry| SEVERITY_ORDER.index(entry[:severity]) || SEVERITY_ORDER.size }
            .filter_map do |entry|
              severity = entry[:severity]
              threshold = entry[:threshold]
              count = @counts[severity]

              next if count <= threshold

              { severity: severity, count: count, threshold: threshold }
            end
        end
      end

      def apply(metadata: {})
        return unless risk_severity_rule?

        vulnerabilities = Array(metadata[:vulnerabilities])
        return result(ACTION_ALLOWED) if vulnerabilities.empty?

        remaining = filter_excepted_vulnerabilities(vulnerabilities)
        return result(ACTION_ALLOWED, REASON_EXCEPTION) if remaining.empty?

        exceeded = SeverityTally.new(remaining).exceeded(denied)
        return result(ACTION_ALLOWED) if exceeded.empty?

        result(ACTION_DENIED, REASON_EVALUATION, details: { exceeded: exceeded })
      end

      private

      def filter_excepted_vulnerabilities(vulnerabilities)
        return vulnerabilities if exception_ids.empty?

        vulnerabilities.reject { |vuln| exception_ids.include?(vuln[:id]) }
      end

      # Duplicated from VulnerabilityRule, which keeps it private with no shared mixin. Lifting it
      # to the base class is a wider refactor than this rule needs.
      def exception_ids
        @exception_ids ||= exceptions.filter_map { |exception| exception[:id] }.to_set
      end
    end
  end
end
