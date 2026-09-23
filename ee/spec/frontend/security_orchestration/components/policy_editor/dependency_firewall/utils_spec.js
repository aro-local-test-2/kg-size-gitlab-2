import {
  buildEmptyRule,
  buildDefaultRuleForType,
  getAddRuleTypeItems,
  getRuleListKey,
  getRuleList,
  isRuleEmpty,
  toggleRuleListKey,
  namesToItems,
  itemsToNames,
  exceptionsToLines,
  linesToExceptions,
  ruleWithUpdatedExceptions,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/utils';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_VULNERABILITY,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/constants';

describe('dependency_firewall/utils', () => {
  it('buildEmptyRule returns a rule with no type and a unique id', () => {
    expect(buildEmptyRule()).toMatchObject({ type: '' });
    expect(buildEmptyRule().id).not.toBe(buildEmptyRule().id);
  });

  it.each`
    type                       | expected
    ${RULE_TYPE_LICENSE}       | ${{ type: RULE_TYPE_LICENSE, denied: [] }}
    ${RULE_TYPE_VULNERABILITY} | ${{ type: RULE_TYPE_VULNERABILITY, denied: [{ severity: 'high' }] }}
    ${RULE_TYPE_MALICIOUS}     | ${{ type: RULE_TYPE_MALICIOUS, denied: [{ is_malicious: true }] }}
    ${RULE_TYPE_RISK_SEVERITY} | ${{ type: RULE_TYPE_RISK_SEVERITY, denied: [{ severity: 'high', threshold: 0 }] }}
  `('buildDefaultRuleForType($type) returns $expected', ({ type, expected }) => {
    expect(buildDefaultRuleForType(type)).toMatchObject(expected);
  });

  it('buildDefaultRuleForType gives each rule a unique id', () => {
    expect(buildDefaultRuleForType(RULE_TYPE_LICENSE).id).not.toBe(
      buildDefaultRuleForType(RULE_TYPE_LICENSE).id,
    );
  });

  it('buildDefaultRuleForType returns empty rule for unrecognized type', () => {
    expect(buildDefaultRuleForType('unknown')).toMatchObject({ type: '' });
  });

  describe('getAddRuleTypeItems', () => {
    describe('when the flag is off', () => {
      let values;

      beforeEach(() => {
        values = getAddRuleTypeItems(false).map(({ value }) => value);
      });

      it('offers vulnerability instead of risk_severity', () => {
        expect(values).toContain(RULE_TYPE_VULNERABILITY);
        expect(values).not.toContain(RULE_TYPE_RISK_SEVERITY);
      });

      it('offers license and malicious', () => {
        expect(values).toEqual(expect.arrayContaining([RULE_TYPE_LICENSE, RULE_TYPE_MALICIOUS]));
      });
    });

    describe('when the flag is on', () => {
      let values;

      beforeEach(() => {
        values = getAddRuleTypeItems(true).map(({ value }) => value);
      });

      it('offers risk_severity instead of vulnerability', () => {
        expect(values).toContain(RULE_TYPE_RISK_SEVERITY);
        expect(values).not.toContain(RULE_TYPE_VULNERABILITY);
      });

      it('offers license and malicious', () => {
        expect(values).toEqual(expect.arrayContaining([RULE_TYPE_LICENSE, RULE_TYPE_MALICIOUS]));
      });
    });
  });

  it('getRuleListKey returns "denied" when the rule has a denied list', () => {
    expect(getRuleListKey({ type: RULE_TYPE_LICENSE, denied: [] })).toBe('denied');
  });

  it('getRuleListKey returns "allowed" when the rule has an allowed list', () => {
    expect(getRuleListKey({ type: RULE_TYPE_LICENSE, allowed: [] })).toBe('allowed');
  });

  it('getRuleList returns the array under whichever key is present', () => {
    expect(getRuleList({ type: RULE_TYPE_LICENSE, allowed: [{ name: 'MIT' }] })).toEqual([
      { name: 'MIT' },
    ]);
  });

  it('isRuleEmpty returns true when the active list is empty', () => {
    expect(isRuleEmpty({ type: RULE_TYPE_LICENSE, denied: [] })).toBe(true);
  });

  it('isRuleEmpty returns false when the active list has entries', () => {
    expect(isRuleEmpty({ type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] })).toBe(false);
  });

  it('toggleRuleListKey moves the existing list to the new key', () => {
    expect(
      toggleRuleListKey({ type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] }, 'allowed'),
    ).toEqual({
      type: RULE_TYPE_LICENSE,
      allowed: [{ name: 'MIT' }],
    });
  });

  it('namesToItems/itemsToNames round-trip', () => {
    const names = ['MIT', 'GPL-3.0'];
    expect(itemsToNames(namesToItems(names))).toEqual(names);
  });

  it('exceptionsToLines/linesToExceptions round-trip for purls', () => {
    const exceptions = [{ purl: 'pkg:npm/lodash@4.17.21' }];
    expect(linesToExceptions(exceptionsToLines(exceptions))).toEqual(exceptions);
  });

  it('exceptionsToLines/linesToExceptions round-trip for ids', () => {
    const exceptions = [{ id: 'CVE-2021-23337' }];
    expect(linesToExceptions(exceptionsToLines(exceptions))).toEqual(exceptions);
  });

  it('linesToExceptions infers purl for pkg: lines and id for everything else', () => {
    expect(linesToExceptions(['pkg:npm/lodash@4.17.21', 'CVE-2021-23337'])).toEqual([
      { purl: 'pkg:npm/lodash@4.17.21' },
      { id: 'CVE-2021-23337' },
    ]);
  });

  describe('ruleWithUpdatedExceptions', () => {
    it('adds exceptions inferring purl/id per line', () => {
      const rule = { type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] };

      expect(ruleWithUpdatedExceptions(rule, ['pkg:npm/lodash@4.17.21', 'CVE-2021-23337'])).toEqual(
        {
          type: RULE_TYPE_LICENSE,
          denied: [{ name: 'MIT' }],
          exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }, { id: 'CVE-2021-23337' }],
        },
      );
    });

    it('removes the exceptions key entirely when the list is cleared', () => {
      const rule = {
        type: RULE_TYPE_LICENSE,
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      };

      const updated = ruleWithUpdatedExceptions(rule, []);

      expect(updated).toEqual({ type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] });
      expect(updated).not.toHaveProperty('exceptions');
    });
  });
});
