import {
  deserializePolicyData,
  deserializeScope,
  emptyPolicyData,
  serializePolicyData,
  serializePolicyParams,
  serializeScope,
} from 'ee/policy_store/components/editor/serializer';

describe('policy data serializer', () => {
  const formState = {
    trigger: 'deployment_requested',
    triggerConfig: {},
    rules: ['custom', 'environment'],
    ruleConfigs: {
      custom: { policy: 'package governance' },
      environment: { names: ['production'] },
    },
    actions: ['require_approval'],
    actionConfigs: { require_approval: { roles: ['maintainer'] } },
  };

  describe('serializePolicyData', () => {
    it('puts the Rego program in `value` directly, which is where the gate reads it', () => {
      const { rules } = serializePolicyData(formState);

      expect(rules[0]).toEqual({ type: 'custom', value: 'package governance' });
    });

    it('puts a typed rule config in `value` as an object', () => {
      const { rules } = serializePolicyData(formState);

      expect(rules[1]).toEqual({ type: 'environment', value: { names: ['production'] } });
    });

    it('drops an all-blank freeze window but keeps a partially filled one', () => {
      const { rules } = serializePolicyData({
        trigger: 'deployment_requested',
        rules: ['calendar'],
        ruleConfigs: {
          calendar: {
            windows: [
              { name: '', tiers: [], starts_at: '', ends_at: '' },
              { name: 'eoq', tiers: [], starts_at: '', ends_at: '' },
            ],
          },
        },
      });

      expect(rules[0]).toEqual({
        type: 'calendar',
        value: { windows: [{ name: 'eoq', tiers: [], starts_at: '', ends_at: '' }] },
      });
    });

    // The transpiler de-duplicates windows before compiling, so a duplicate
    // kept here would show on the detail page as a window the program does
    // not separately carry.
    it('drops a duplicate freeze window, ignoring the order tiers were picked in', () => {
      const window = {
        name: 'eoq',
        tiers: ['production', 'staging'],
        starts_at: '2026-12-24T00:00:00Z',
        ends_at: '2027-01-02T00:00:00Z',
      };
      const { rules } = serializePolicyData({
        trigger: 'deployment_requested',
        rules: ['calendar'],
        ruleConfigs: {
          calendar: {
            windows: [window, { ...window, tiers: ['staging', 'production'] }],
          },
        },
      });

      expect(rules[0].value.windows).toEqual([window]);
    });

    it('keeps windows that differ only by one bound', () => {
      const window = {
        name: 'eoq',
        tiers: ['production'],
        starts_at: '2026-12-24T00:00:00Z',
        ends_at: '2027-01-02T00:00:00Z',
      };
      const later = { ...window, ends_at: '2027-01-03T00:00:00Z' };
      const { rules } = serializePolicyData({
        trigger: 'deployment_requested',
        rules: ['calendar'],
        ruleConfigs: { calendar: { windows: [window, later] } },
      });

      expect(rules[0].value.windows).toEqual([window, later]);
    });

    it('puts an action config in `value`, the only config key the API persists', () => {
      const { actions } = serializePolicyData(formState);

      expect(actions).toEqual([{ type: 'require_approval', value: { roles: ['maintainer'] } }]);
    });

    it('exposes the trigger as trigger_type', () => {
      expect(serializePolicyData(formState).trigger_type).toBe('deployment_requested');
    });

    it('serializes an empty policy without throwing', () => {
      expect(serializePolicyData(emptyPolicyData())).toEqual({
        trigger_type: null,
        rules: [],
        actions: [],
      });
    });

    it('serializes with no argument at all', () => {
      expect(serializePolicyData()).toEqual({
        trigger_type: null,
        rules: [],
        actions: [],
      });
    });

    it('defaults a missing rule config to an empty value', () => {
      const { rules } = serializePolicyData({ rules: ['environment'] });

      expect(rules).toEqual([{ type: 'environment', value: {} }]);
    });

    it('defaults a missing action config to an empty value', () => {
      const { actions } = serializePolicyData({ actions: ['block'] });

      expect(actions).toEqual([{ type: 'block', value: {} }]);
    });

    it('defaults a missing Rego program to an empty string, not undefined', () => {
      const { rules } = serializePolicyData({ rules: ['custom'] });

      expect(rules).toEqual([{ type: 'custom', value: '' }]);
    });
  });

  describe('round trip', () => {
    it('returns the original form state', () => {
      expect(deserializePolicyData(serializePolicyData(formState))).toEqual(formState);
    });

    it('survives a policy with no rules or actions', () => {
      const empty = emptyPolicyData();

      expect(deserializePolicyData(serializePolicyData(empty))).toEqual(empty);
    });
  });

  describe('deserializePolicyData', () => {
    it('drops value keys the catalog no longer declares for the rule', () => {
      const { ruleConfigs } = deserializePolicyData({
        trigger_type: 'deployment_requested',
        rules: [
          {
            type: 'calendar',
            value: { windowStart: '2026-12-20T00:00:00Z', recurring: 'weekly', windows: [] },
          },
        ],
      });

      expect(ruleConfigs.calendar).toEqual({ windows: [] });
    });

    it('keeps the whole value for a rule type the catalog does not know', () => {
      const { ruleConfigs } = deserializePolicyData({
        trigger_type: 'deployment_requested',
        rules: [{ type: 'brand_new', value: { anything: 'goes' } }],
      });

      expect(ruleConfigs.brand_new).toEqual({ anything: 'goes' });
    });

    it('returns empty form state for a policy with nothing set', () => {
      expect(deserializePolicyData({})).toEqual(emptyPolicyData());
    });

    it('returns empty form state with no argument', () => {
      expect(deserializePolicyData()).toEqual(emptyPolicyData());
    });

    it('reads the persisted trigger_type back as the selected trigger', () => {
      expect(deserializePolicyData({ trigger_type: 'deployment_requested' }).trigger).toBe(
        'deployment_requested',
      );
    });

    it('unwraps the Rego program back into the code field', () => {
      const { ruleConfigs } = deserializePolicyData({
        rules: [{ type: 'custom', value: 'package foo' }],
      });

      expect(ruleConfigs.custom).toEqual({ policy: 'package foo' });
    });

    it('tolerates a Rego rule with no value', () => {
      const { ruleConfigs } = deserializePolicyData({ rules: [{ type: 'custom' }] });

      expect(ruleConfigs.custom).toEqual({ policy: '' });
    });

    it('tolerates an action with no value', () => {
      const { actionConfigs } = deserializePolicyData({ actions: [{ type: 'block' }] });

      expect(actionConfigs.block).toEqual({});
    });

    it('keeps the first occurrence of a duplicated rule type', () => {
      const { rules, ruleConfigs } = deserializePolicyData({
        rules: [
          { type: 'custom', value: 'package first' },
          { type: 'custom', value: 'package second' },
        ],
      });

      expect(rules).toEqual(['custom']);
      expect(ruleConfigs).toEqual({ custom: { policy: 'package first' } });
    });

    it('keeps the first occurrence of a duplicated action type', () => {
      const { actions, actionConfigs } = deserializePolicyData({
        actions: [
          { type: 'require_approval', value: { approvals_required: 1 } },
          { type: 'require_approval', value: { approvals_required: 5 } },
        ],
      });

      expect(actions).toEqual(['require_approval']);
      expect(actionConfigs).toEqual({ require_approval: { approvals_required: 1 } });
    });
  });

  describe('serializeScope', () => {
    const projects = [
      { id: 'gid://gitlab/Project/7', fullPath: 'flightjs/one' },
      { id: 'gid://gitlab/Project/9', fullPath: 'flightjs/two' },
    ];

    it('serializes "all projects" with no exclusions to an empty scope', () => {
      expect(serializeScope({ mode: 'all', projects: [], exclusions: [] })).toEqual({});
    });

    it('serializes with no argument to an empty scope', () => {
      expect(serializeScope()).toEqual({});
    });

    it('serializes specific projects to a plain list of numeric ids', () => {
      expect(serializeScope({ mode: 'specific', projects, exclusions: [] })).toEqual({
        projects: { including: [7, 9] },
      });
    });

    it('serializes exclusions independently of the mode', () => {
      expect(serializeScope({ mode: 'all', projects: [], exclusions: projects })).toEqual({
        projects: { excluding: [7, 9] },
      });
    });

    it('ignores selected projects left over from a previous "specific" choice', () => {
      expect(serializeScope({ mode: 'all', projects, exclusions: [] })).toEqual({});
    });
  });

  describe('deserializeScope', () => {
    it('reads an empty scope as "all projects"', () => {
      expect(deserializeScope({})).toEqual({ mode: 'all', projects: [], exclusions: [] });
    });

    it('reads a missing scope as "all projects"', () => {
      expect(deserializeScope(undefined)).toEqual({ mode: 'all', projects: [], exclusions: [] });
    });

    it('reads included project ids back as "specific" with GraphQL id stubs', () => {
      expect(deserializeScope({ projects: { including: [7, 9] } })).toEqual({
        mode: 'specific',
        projects: [{ id: 'gid://gitlab/Project/7' }, { id: 'gid://gitlab/Project/9' }],
        exclusions: [],
      });
    });

    it('reads `{ id }` hash entries the same as bare ids', () => {
      expect(deserializeScope({ projects: { including: [{ id: 7 }] } })).toEqual({
        mode: 'specific',
        projects: [{ id: 'gid://gitlab/Project/7' }],
        exclusions: [],
      });
    });

    it('reads excluded project ids back as exclusions, skipping typed entries', () => {
      expect(deserializeScope({ projects: { excluding: [7, { type: 'personal' }] } })).toEqual({
        mode: 'all',
        projects: [],
        exclusions: [{ id: 'gid://gitlab/Project/7' }],
      });
    });
  });

  describe('serializePolicyParams', () => {
    it('builds the full request params for the write endpoints', () => {
      expect(
        serializePolicyParams({
          name: 'Production gate',
          description: 'Gates production deployments',
          mode: 'enforce',
          scope: {
            mode: 'specific',
            projects: [{ id: 'gid://gitlab/Project/7' }],
            exclusions: [],
          },
          policyData: formState,
        }),
      ).toEqual({
        name: 'Production gate',
        description: 'Gates production deployments',
        mode: 'enforce',
        policy_scope: { projects: { including: [7] } },
        trigger_type: 'deployment_requested',
        rules: [
          { type: 'custom', value: 'package governance' },
          { type: 'environment', value: { names: ['production'] } },
        ],
        actions: [{ type: 'require_approval', value: { roles: ['maintainer'] } }],
      });
    });

    it('trims surrounding whitespace from the name', () => {
      expect(
        serializePolicyParams({
          name: '  Production gate ',
          description: '',
          mode: 'enforce',
          scope: { mode: 'all', projects: [], exclusions: [] },
          policyData: formState,
        }),
      ).toMatchObject({ name: 'Production gate' });
    });
  });
});
