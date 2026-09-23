# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Security::DependencyFirewallPolicies::RiskSeverityRule, feature_category: :dependency_firewall do
  let(:package) { { purl_type: 'npm', name: 'lodash', version: '4.17.15' } }
  let(:rule) { { type: 'risk_severity', denied: [{ severity: 'high', threshold: 2 }] } }
  let(:vulnerabilities) { [] }

  subject(:evaluation) { described_class.new(rule).evaluate(package, metadata: { vulnerabilities: vulnerabilities }) }

  def vulns(severity, count)
    Array.new(count) { |i| { id: "CVE-2024-#{severity}-#{i}", severity: severity } }
  end

  context 'when there are no vulnerabilities' do
    it { is_expected.to eq({ action: :allowed, reason: :evaluation }) }
  end

  context 'when the count is at the threshold' do
    let(:vulnerabilities) { vulns('high', 2) }

    it 'allows, because only strictly more than the threshold denies' do
      expect(evaluation).to eq({ action: :allowed, reason: :evaluation })
    end
  end

  context 'when the count is one over the threshold' do
    let(:vulnerabilities) { vulns('high', 3) }

    it 'denies and reports the tally against the ceiling' do
      expect(evaluation).to eq(
        action: :denied,
        reason: :evaluation,
        details: { exceeded: [{ severity: 'high', count: 3, threshold: 2 }] }
      )
    end
  end

  context 'with a threshold of zero' do
    let(:rule) { { type: 'risk_severity', denied: [{ severity: 'critical', threshold: 0 }] } }
    let(:vulnerabilities) { vulns('critical', 1) }

    it 'denies on a single vulnerability' do
      expect(evaluation).to eq(
        action: :denied,
        reason: :evaluation,
        details: { exceeded: [{ severity: 'critical', count: 1, threshold: 0 }] }
      )
    end
  end

  context 'when a severity is absent from denied' do
    let(:vulnerabilities) { vulns('low', 50) }

    it 'is not evaluated at all' do
      expect(evaluation).to eq({ action: :allowed, reason: :evaluation })
    end
  end

  context 'when several severities are over their thresholds' do
    let(:rule) do
      { type: 'risk_severity',
        denied: [{ severity: 'low', threshold: 0 }, { severity: 'critical', threshold: 0 },
          { severity: 'high', threshold: 1 }] }
    end

    let(:vulnerabilities) { vulns('critical', 1) + vulns('high', 2) + vulns('low', 1) }

    it 'reports every exceeded severity, ordered critical first regardless of policy order' do
      expect(evaluation[:details][:exceeded]).to eq(
        [{ severity: 'critical', count: 1, threshold: 0 },
          { severity: 'high', count: 2, threshold: 1 },
          { severity: 'low', count: 1, threshold: 0 }]
      )
    end
  end

  # The fetch service emits one entry per affected-package row, and rows differing only by
  # distro_version share an advisory, so the same CVE can arrive more than once.
  context 'when the same vulnerability arrives more than once' do
    let(:rule) { { type: 'risk_severity', denied: [{ severity: 'high', threshold: 1 }] } }
    let(:vulnerabilities) do
      [{ id: 'CVE-2024-0001', severity: 'high' }, { id: 'CVE-2024-0001', severity: 'high' }]
    end

    it 'counts it once, so a duplicate cannot push the tally over the threshold' do
      expect(evaluation).to eq({ action: :allowed, reason: :evaluation })
    end
  end

  # The fetch service emits 'unknown' when no CVSS vector is valid, and the cvss-suite gem can
  # return 'none' for a zero score. A policy can name neither, because the JSON schema restricts
  # `severity` to critical/high/medium/low.
  context 'with vulnerabilities whose severity no denied entry names' do
    let(:rule) { { type: 'risk_severity', denied: [{ severity: 'high', threshold: 0 }] } }
    let(:vulnerabilities) { vulns('unknown', 5) + vulns('none', 5) }

    it 'does not tally them against a named severity' do
      expect(evaluation).to eq({ action: :allowed, reason: :evaluation })
    end
  end

  # Pins where that exclusion actually lives. This rule tallies whatever the policy names, so the
  # schema is the only thing keeping an unscored severity out of a threshold.
  context 'with a schema-forbidden severity reaching the rule anyway' do
    let(:rule) { { type: 'risk_severity', denied: [{ severity: 'unknown', threshold: 0 }] } }
    let(:vulnerabilities) { vulns('unknown', 1) }

    it 'tallies it, because the exclusion is schema-enforced and not guarded here' do
      expect(evaluation).to eq(
        action: :denied,
        reason: :evaluation,
        details: { exceeded: [{ severity: 'unknown', count: 1, threshold: 0 }] }
      )
    end
  end

  context 'when the package is excepted by PURL' do
    let(:rule) do
      { type: 'risk_severity', denied: [{ severity: 'high', threshold: 0 }],
        exceptions: [{ purl: 'pkg:npm/lodash' }] }
    end

    let(:vulnerabilities) { vulns('high', 9) }

    it 'short-circuits before the tally' do
      expect(evaluation).to eq({ action: :allowed, reason: :exception })
    end
  end

  context 'when every vulnerability is excepted by CVE' do
    let(:rule) do
      { type: 'risk_severity', denied: [{ severity: 'high', threshold: 0 }],
        exceptions: [{ id: 'CVE-2024-high-0' }, { id: 'CVE-2024-high-1' }] }
    end

    let(:vulnerabilities) { vulns('high', 2) }

    it 'allows, having removed them before the tally' do
      expect(evaluation).to eq({ action: :allowed, reason: :exception })
    end
  end

  context 'when a CVE exception drops the count to the threshold' do
    let(:rule) do
      { type: 'risk_severity', denied: [{ severity: 'high', threshold: 2 }],
        exceptions: [{ id: 'CVE-2024-high-0' }] }
    end

    let(:vulnerabilities) { vulns('high', 3) }

    it 'allows, because the exception applies before counting' do
      expect(evaluation).to eq({ action: :allowed, reason: :evaluation })
    end
  end

  context 'when the rule is for another type' do
    let(:rule) { { type: 'license', denied: [{ name: 'MIT' }] } }

    it 'declines to evaluate' do
      expect(evaluation).to be_nil
    end
  end
end
