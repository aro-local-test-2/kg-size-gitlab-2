import {
  humanizeRule,
  humanizeRules,
} from 'ee/security_orchestration/components/policy_drawer/dependency_firewall/utils';

describe('humanizeRule', () => {
  describe('license rule', () => {
    it('returns the license subheader and deny-allow items for a denied rule', () => {
      const rule = { type: 'license', denied: [{ name: 'GPL-3.0' }] };

      expect(humanizeRule(rule)).toMatchObject({
        subheader:
          'This policy applies when the license for a dependency matches any of the following criteria:',
        isDenied: true,
        items: [{ license: { text: 'GPL-3.0', value: 'GPL-3.0' }, exceptions: [] }],
      });
    });

    it('uses the allowed list when denied is absent', () => {
      const rule = { type: 'license', allowed: [{ name: 'MIT' }] };

      expect(humanizeRule(rule)).toMatchObject({
        isDenied: false,
        items: [{ license: { text: 'MIT' } }],
      });
    });

    it('associates exceptions with every item in the rule', () => {
      const rule = {
        type: 'license',
        denied: [{ name: 'GPL-3.0' }],
        exceptions: [{ purl: 'pkg:npm/known-gpl-package@1.0.0' }],
      };

      expect(humanizeRule(rule).items[0].exceptions).toEqual(['pkg:npm/known-gpl-package@1.0.0']);
    });

    it('falls back to license rendering when rule.type is missing', () => {
      const rule = { denied: [{ name: 'GPL-3.0' }] };

      expect(humanizeRule(rule)).toMatchObject({ items: [{ license: { text: 'GPL-3.0' } }] });
    });

    it('falls back to license rendering when rule.type is null', () => {
      const rule = { type: null, denied: [{ name: 'GPL-3.0' }] };

      expect(humanizeRule(rule)).toMatchObject({ items: [{ license: { text: 'GPL-3.0' } }] });
    });

    it('treats a null exceptions key (bare `exceptions:` in hand-edited YAML) as empty', () => {
      const rule = { type: 'license', denied: [{ name: 'GPL-3.0' }], exceptions: null };

      expect(() => humanizeRule(rule)).not.toThrow();
      expect(humanizeRule(rule).items[0].exceptions).toEqual([]);
    });
  });

  describe('unrecognized rule type', () => {
    it('returns a placeholder instead of misreading the data as a license rule', () => {
      const rule = { type: 'age', denied: [{ value: 90, interval: 'day' }] };

      expect(humanizeRule(rule)).toEqual({
        subheader: "This policy applies to a rule type that can't be displayed yet.",
      });
    });
  });

  describe('malicious rule', () => {
    it('returns the malicious subheader with no items or criteria list', () => {
      const rule = { type: 'malicious', denied: [{ is_malicious: true }] };

      expect(humanizeRule(rule)).toEqual({
        subheader: 'This policy applies when a dependency is flagged as malicious.',
      });
    });

    it('mentions exceptions in the subheader when present', () => {
      const rule = {
        type: 'malicious',
        denied: [{ is_malicious: true }],
        exceptions: [{ purl: 'pkg:npm/known-safe-package@1.0.0' }],
      };

      expect(humanizeRule(rule).subheader).toBe(
        'This policy applies when a dependency is flagged as malicious, except for: pkg:npm/known-safe-package@1.0.0.',
      );
    });
  });

  describe('risk_severity rule', () => {
    it('returns one criteria line per severity/threshold pair, using strict "more than" wording', () => {
      const rule = {
        type: 'risk_severity',
        denied: [
          { severity: 'high', threshold: 80 },
          { severity: 'critical', threshold: 90 },
        ],
      };

      expect(humanizeRule(rule)).toEqual({
        subheader:
          'This policy applies when the risk severity for a dependency matches any of the following criteria:',
        criteriaList: [
          'Risk severity is high with a risk score of more than 80.',
          'Risk severity is critical with a risk score of more than 90.',
        ],
      });
    });

    it('appends an exceptions criteria line when exceptions are present', () => {
      const rule = {
        type: 'risk_severity',
        denied: [{ severity: 'high', threshold: 80 }],
        exceptions: [{ purl: 'pkg:npm/known-safe-package@1.0.0' }],
      };

      expect(humanizeRule(rule).criteriaList).toEqual([
        'Risk severity is high with a risk score of more than 80.',
        'Except for: pkg:npm/known-safe-package@1.0.0.',
      ]);
    });
  });

  describe('vulnerability rule', () => {
    it('returns one denied-severity criteria line per denied entry', () => {
      const rule = { type: 'vulnerability', denied: [{ severity: 'critical' }] };

      expect(humanizeRule(rule)).toEqual({
        subheader:
          'This policy applies when the vulnerability severity for a dependency matches any of the following criteria:',
        criteriaList: ['Denied severity: critical.'],
      });
    });

    it('returns an allowed-severity criteria line when denied is absent', () => {
      const rule = { type: 'vulnerability', allowed: [{ severity: 'low' }] };

      expect(humanizeRule(rule).criteriaList).toEqual(['Allowed severity: low.']);
    });

    it('ignores an empty denied list and reads from allowed instead', () => {
      const rule = { type: 'vulnerability', denied: [], allowed: [{ severity: 'low' }] };

      expect(humanizeRule(rule).criteriaList).toEqual(['Allowed severity: low.']);
    });

    it('appends an exceptions criteria line when exceptions are present', () => {
      const rule = {
        type: 'vulnerability',
        denied: [{ severity: 'critical' }],
        exceptions: [{ id: 'CVE-2024-1234' }],
      };

      expect(humanizeRule(rule).criteriaList).toEqual([
        'Denied severity: critical.',
        'Except for: CVE-2024-1234.',
      ]);
    });
  });
});

describe('humanizeRules', () => {
  it('keys each rule by its content so identical types at the same index still differ', () => {
    const ruleA = { type: 'license', denied: [{ name: 'GPL-3.0' }] };
    const ruleB = { type: 'license', denied: [{ name: 'MIT' }] };

    const [keyA] = humanizeRules([ruleA]).map((rule) => rule.key);
    const [keyB] = humanizeRules([ruleB]).map((rule) => rule.key);

    expect(keyA).not.toBe(keyB);
  });

  it('returns an empty array for no rules', () => {
    expect(humanizeRules()).toEqual([]);
  });

  it('does not throw when rules is explicitly null', () => {
    expect(humanizeRules(null)).toEqual([]);
  });

  it('blanks out a repeated identical subheader for consecutive same-type rules', () => {
    const rules = [
      { type: 'license', denied: [{ name: 'GPL-3.0' }] },
      { type: 'license', allowed: [{ name: 'MIT' }] },
    ];

    expect(humanizeRules(rules).map((rule) => rule.subheader)).toEqual([
      'This policy applies when the license for a dependency matches any of the following criteria:',
      '',
    ]);
  });

  it('does not blank the subheader when it differs from the previous rule', () => {
    const rules = [
      { type: 'license', denied: [{ name: 'GPL-3.0' }] },
      { type: 'malicious', denied: [{ is_malicious: true }] },
    ];

    const subheaders = humanizeRules(rules).map((rule) => rule.subheader);

    expect(subheaders[0]).not.toBe('');
    expect(subheaders[1]).not.toBe('');
  });

  it('re-shows a subheader that repeats non-consecutively', () => {
    const rules = [
      { type: 'license', denied: [{ name: 'GPL-3.0' }] },
      { type: 'malicious', denied: [{ is_malicious: true }] },
      { type: 'license', allowed: [{ name: 'MIT' }] },
    ];

    const subheaders = humanizeRules(rules).map((rule) => rule.subheader);

    expect(subheaders[0]).not.toBe('');
    expect(subheaders[2]).not.toBe('');
  });

  it('does not blank a repeated subheader for rule types with no items or criteriaList to fall back on', () => {
    const rules = [
      { type: 'malicious', denied: [{ is_malicious: true }] },
      { type: 'malicious', denied: [{ is_malicious: true }] },
    ];

    const humanized = humanizeRules(rules);

    expect(humanized[0].subheader).not.toBe('');
    expect(humanized[1].subheader).not.toBe('');
  });

  it('does not blank a repeated placeholder subheader for consecutive unrecognized rule types', () => {
    const rules = [
      { type: 'age', denied: [{ value: 30, interval: 'day' }] },
      { type: 'age', denied: [{ value: 90, interval: 'day' }] },
    ];

    const humanized = humanizeRules(rules);

    expect(humanized[0].subheader).not.toBe('');
    expect(humanized[1].subheader).not.toBe('');
  });
});
