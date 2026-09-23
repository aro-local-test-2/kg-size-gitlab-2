import { ruleConfigBlockers } from 'ee/policy_store/catalog/validation';
import { RULES } from 'ee/policy_store/catalog/rules';

describe('ruleConfigBlockers', () => {
  const catalog = [
    {
      id: 'needy',
      label: 'Needy Rule',
      fields: [
        { key: 'code', label: 'Code block', required: true },
        { key: 'note', label: 'Note' },
      ],
    },
    {
      id: 'either',
      label: 'Either Rule',
      requireOneOf: ['names', 'tiers'],
      fields: [
        { key: 'names', label: 'Names' },
        { key: 'tiers', label: 'Tiers' },
      ],
    },
  ];

  it('returns nothing when every required field is filled', () => {
    expect(ruleConfigBlockers(catalog, ['needy'], { needy: { code: 'x' } })).toEqual([]);
  });

  it.each([undefined, '', '   '])('flags a required field left as %p', (code) => {
    expect(ruleConfigBlockers(catalog, ['needy'], { needy: { code } })).toEqual([
      'Needy Rule is missing Code block.',
    ]);
  });

  it('flags a missing config object the same as blank fields', () => {
    expect(ruleConfigBlockers(catalog, ['needy'])).toEqual(['Needy Rule is missing Code block.']);
  });

  it('does not flag optional fields', () => {
    expect(ruleConfigBlockers(catalog, ['needy'], { needy: { code: 'x', note: '' } })).toEqual([]);
  });

  it('flags a requireOneOf entry only when every alternative is blank', () => {
    expect(ruleConfigBlockers(catalog, ['either'], { either: { names: [], tiers: [] } })).toEqual([
      'Either Rule needs at least one of: Names, Tiers.',
    ]);
    expect(ruleConfigBlockers(catalog, ['either'], { either: { tiers: ['production'] } })).toEqual(
      [],
    );
  });

  it('produces no blockers for a rule the catalog does not know', () => {
    expect(ruleConfigBlockers(catalog, ['retired_rule'], {})).toEqual([]);
  });

  it('treats an object value with no keys as blank', () => {
    const objectCatalog = [
      {
        id: 'matrix',
        label: 'Matrix Rule',
        fields: [{ key: 'sla', label: 'SLA', required: true }],
      },
    ];

    expect(ruleConfigBlockers(objectCatalog, ['matrix'], { matrix: { sla: {} } })).toEqual([
      'Matrix Rule is missing SLA.',
    ]);
    expect(ruleConfigBlockers(objectCatalog, ['matrix'], { matrix: { sla: { high: 7 } } })).toEqual(
      [],
    );
  });

  it('ignores an empty requireOneOf declaration instead of blocking forever', () => {
    const emptyCatalog = [{ id: 'odd', label: 'Odd Rule', requireOneOf: [], fields: [] }];

    expect(ruleConfigBlockers(emptyCatalog, ['odd'], {})).toEqual([]);
  });

  it('does not HTML-escape labels, because the sentences render as text', () => {
    const quotedCatalog = [
      {
        id: 'quoted',
        label: "Ma'am's Rule",
        fields: [{ key: 'code', label: "Noms d'environnement", required: true }],
      },
    ];

    expect(ruleConfigBlockers(quotedCatalog, ['quoted'], {})).toEqual([
      "Ma'am's Rule is missing Noms d'environnement.",
    ]);
  });

  describe('firstStatement declarations', () => {
    const regoCatalog = [
      {
        id: 'rego',
        label: 'Rego Rule',
        fields: [
          { key: 'code', label: 'Program', required: true, firstStatement: 'package governance' },
        ],
      },
    ];

    it('flags a program opening with a different statement', () => {
      expect(
        ruleConfigBlockers(regoCatalog, ['rego'], { rego: { code: 'package other\n\nallow' } }),
      ).toEqual(['Program in Rego Rule must open with package governance.']);
    });

    it('reads past comments and blank lines to find the first statement', () => {
      const code = '# header comment\n\n  package governance # trailing\nallow';

      expect(ruleConfigBlockers(regoCatalog, ['rego'], { rego: { code } })).toEqual([]);
    });

    it('reports only the missing-field blocker when the program is blank', () => {
      expect(ruleConfigBlockers(regoCatalog, ['rego'], { rego: { code: '' } })).toEqual([
        'Rego Rule is missing Program.',
      ]);
    });
  });

  it('collects blockers across all selected rules in order', () => {
    expect(ruleConfigBlockers(catalog, ['needy', 'either'], {})).toEqual([
      'Needy Rule is missing Code block.',
      'Either Rule needs at least one of: Names, Tiers.',
    ]);
  });

  // Pins the live catalog's declarations so the store's actual requirements
  // (an empty Rego program cannot compile; the environment rule needs a name
  // or a tier) cannot be dropped silently.
  describe('with the real rules catalog', () => {
    it('blocks a custom rule without Rego', () => {
      expect(ruleConfigBlockers(RULES, ['custom'], { custom: { policy: '' } })).toEqual([
        'Custom Rule (Rego) is missing Rego policy definition.',
      ]);
    });

    it('blocks a custom rule whose program does not open with package governance', () => {
      expect(
        ruleConfigBlockers(RULES, ['custom'], { custom: { policy: 'package mine\n\nallow' } }),
      ).toEqual([
        'Rego policy definition in Custom Rule (Rego) must open with package governance.',
      ]);
    });

    it('accepts the shipped default template', () => {
      const custom = RULES.find(({ id }) => id === 'custom');
      const { default: template } = custom.fields.find(({ key }) => key === 'policy');

      // The default must satisfy the field's own requirements, or a freshly
      // added custom rule would be born blocked.
      expect(template).toEqual(expect.any(String));
      expect(ruleConfigBlockers(RULES, ['custom'], { custom: { policy: template } })).toEqual([]);
    });

    it('blocks an environment rule with neither names nor tiers', () => {
      expect(ruleConfigBlockers(RULES, ['environment'], { environment: {} })).toEqual([
        'Environment State needs at least one of: Environment names, Environment tiers.',
      ]);
    });

    it.each([{}, { windows: [] }])('blocks a calendar rule configured as %p', (calendar) => {
      expect(ruleConfigBlockers(RULES, ['calendar'], { calendar })).toEqual([
        'Freeze Window is missing Freeze windows.',
      ]);
    });

    it('accepts a calendar rule once a window is authored', () => {
      const windows = [
        {
          name: 'Year end',
          tiers: ['production'],
          starts_at: '2026-12-24T00:00:00Z',
          ends_at: '2027-01-02T00:00:00Z',
        },
      ];

      expect(ruleConfigBlockers(RULES, ['calendar'], { calendar: { windows } })).toEqual([]);
    });
  });
});
