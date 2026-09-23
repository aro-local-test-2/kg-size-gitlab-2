import Ajv from 'ajv/dist/2020';
import AjvFormats from 'ajv-formats';
import { safeLoad } from 'js-yaml';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EditorComponent, {
  DEFAULT_DEPENDENCY_FIREWALL_POLICY,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/editor_component.vue';
import EditorLayout from 'ee/security_orchestration/components/policy_editor/editor_layout.vue';
import RuleList from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_list.vue';
import EnforcementTypeSelect from 'ee/security_orchestration/components/policy_editor/dependency_firewall/settings/enforcement_type_select.vue';
import DisabledSection from 'ee/security_orchestration/components/policy_editor/disabled_section.vue';
import BypassSettings from 'ee/security_orchestration/components/policy_editor/dependency_firewall/advanced_settings/bypass_settings.vue';
import { buildDefaultRuleForType } from 'ee/security_orchestration/components/policy_editor/dependency_firewall/utils';
import { removeIdsFromPolicy } from 'ee/security_orchestration/components/policy_editor/utils';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_VULNERABILITY,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/constants';
import {
  EDITOR_MODE_RULE,
  EDITOR_MODE_YAML,
} from 'ee/security_orchestration/components/policy_editor/constants';
import PolicySchema from '../../../../../../app/validators/json_schemas/security_orchestration_policy.json';

describe('DependencyFirewallEditorComponent', () => {
  let wrapper;

  const createWrapper = (propsData = {}, glFeatures = { dependencyFirewallPhase2: true }) => {
    wrapper = shallowMountExtended(EditorComponent, {
      propsData: {
        existingPolicy: null,
        isCreating: false,
        isDeleting: false,
        isEditing: false,
        selectedPolicyType: 'dependency_firewall_policy',
        ...propsData,
      },
      provide: { glFeatures },
    });
  };

  const findEditorLayout = () => wrapper.findComponent(EditorLayout);

  it('defaults to rule mode with both modes available', () => {
    createWrapper();
    expect(findEditorLayout().props('defaultEditorMode')).toBe(EDITOR_MODE_RULE);
    expect(findEditorLayout().props('editorModes')).toEqual([
      expect.objectContaining({ value: EDITOR_MODE_RULE }),
      expect.objectContaining({ value: EDITOR_MODE_YAML }),
    ]);
  });

  it('renders the rule list seeded from the default policy YAML with no rules', () => {
    createWrapper();
    expect(wrapper.findComponent(RuleList).props('rules')).toEqual([]);
  });

  it('renders the enforcement type select seeded from the default policy YAML', () => {
    createWrapper();
    expect(wrapper.findComponent(EnforcementTypeSelect).props('enforcementType')).toBe('warn');
  });

  it('updates the yaml editor value when a rule changes', async () => {
    createWrapper();
    const initialYaml = findEditorLayout().props('yamlEditorValue');

    await wrapper.findComponent(RuleList).vm.$emit('changed', [{ type: 'license', denied: [] }]);

    expect(findEditorLayout().props('yamlEditorValue')).not.toBe(initialYaml);
    expect(findEditorLayout().props('yamlEditorValue')).toContain('type: license');
  });

  it('updates the yaml editor value when the enforcement type changes', async () => {
    createWrapper();
    await wrapper.findComponent(EnforcementTypeSelect).vm.$emit('change', 'enforced');
    expect(findEditorLayout().props('yamlEditorValue')).toContain('enforcement_type: enforced');
  });

  it('updates the yaml editor value when a policy property changes', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit('update-property', 'name', 'My DFW Policy');
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: My DFW Policy');
  });

  it('re-parses the policy object when the yaml pane is edited directly', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit(
      'update-yaml',
      'dependency_firewall_policy:\n  - name: x\n    enabled: true\n    enforcement_type: warn\n    rules: []\n',
    );
    expect(wrapper.findComponent(RuleList).props('rules')).toEqual([]);
  });

  it('emits save with the yaml built from the current yaml editor value', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit('save-policy', 'APPEND');
    expect(wrapper.emitted('save')[0][0]).toMatchObject({ action: 'APPEND' });
  });

  it('disables the rules and bypass settings sections when the yaml pane has unparseable content', async () => {
    createWrapper();
    await findEditorLayout().vm.$emit('update-yaml', 'not: valid: yaml: [');

    const disabledSections = wrapper.findAllComponents(DisabledSection);

    expect(disabledSections).toHaveLength(2);
    expect(disabledSections.at(0).props('disabled')).toBe(true);
    expect(disabledSections.at(1).props('disabled')).toBe(true);
  });

  it('renders bypass settings seeded from the default policy YAML', () => {
    createWrapper();
    expect(wrapper.findComponent(BypassSettings).props('bypassSettings')).toEqual({});
  });

  it('updates the yaml editor value when bypass settings change', async () => {
    createWrapper();
    await wrapper
      .findComponent(BypassSettings)
      .vm.$emit('changed', 'bypass_settings', { users: [{ id: 1 }] });

    expect(findEditorLayout().props('yamlEditorValue')).toContain('bypass_settings');
    expect(wrapper.findComponent(BypassSettings).props('bypassSettings')).toEqual({
      users: [{ id: 1 }],
    });
  });
});

describe('DependencyFirewallEditorComponent with an existing policy', () => {
  let wrapper;

  const existingPolicy = {
    name: 'Existing DFW policy',
    description: 'Blocks GPL licenses',
    enabled: true,
    enforcement_type: 'enforced',
    policy_scope: { projects: { excluding: [] } },
    rules: [{ type: 'license', denied: [{ name: 'GPL-3.0' }] }],
    bypass_settings: { users: [{ id: 7 }] },
  };

  const createWrapper = (glFeatures = { dependencyFirewallPhase2: true }) => {
    wrapper = shallowMountExtended(EditorComponent, {
      propsData: {
        existingPolicy,
        isCreating: false,
        isDeleting: false,
        isEditing: true,
        selectedPolicyType: 'dependency_firewall_policy',
      },
      provide: { glFeatures },
    });
  };

  const findEditorLayout = () => wrapper.findComponent(EditorLayout);

  it('seeds the yaml editor and rule list from the existing policy, not the defaults', () => {
    createWrapper();
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Existing DFW policy');
    expect(wrapper.findComponent(RuleList).props('rules')).toEqual([
      expect.objectContaining(existingPolicy.rules[0]),
    ]);
    expect(wrapper.findComponent(EnforcementTypeSelect).props('enforcementType')).toBe('enforced');
    expect(wrapper.findComponent(BypassSettings).props('bypassSettings')).toEqual({
      users: [{ id: 7 }],
    });
  });

  it('still renders the legacy yaml-only view when the flag is disabled', () => {
    createWrapper({ dependencyFirewallPhase2: false });
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Existing DFW policy');
    expect(wrapper.findComponent(RuleList).exists()).toBe(false);
  });
});

describe('DependencyFirewallEditorComponent when dependencyFirewallPhase2 is disabled', () => {
  let wrapper;

  const createWrapper = () => {
    wrapper = shallowMountExtended(EditorComponent, {
      propsData: {
        existingPolicy: null,
        isCreating: false,
        isDeleting: false,
        isEditing: false,
        selectedPolicyType: 'dependency_firewall_policy',
      },
      provide: { glFeatures: { dependencyFirewallPhase2: false } },
    });
  };

  const findEditorLayout = () => wrapper.findComponent(EditorLayout);

  it('defaults to yaml-only mode, hiding the rule builder', () => {
    createWrapper();
    expect(findEditorLayout().props('defaultEditorMode')).toBe(EDITOR_MODE_YAML);
    expect(findEditorLayout().props('editorModes')).toEqual([
      expect.objectContaining({ value: EDITOR_MODE_YAML }),
    ]);
    expect(wrapper.findComponent(RuleList).exists()).toBe(false);
    expect(wrapper.findComponent(EnforcementTypeSelect).exists()).toBe(false);
    expect(wrapper.findComponent(BypassSettings).exists()).toBe(false);
  });

  it('seeds the yaml editor with the legacy example policy', () => {
    createWrapper();
    expect(findEditorLayout().props('yamlEditorValue')).toContain('name: Your policy name');
  });
});

describe('DEFAULT_DEPENDENCY_FIREWALL_POLICY', () => {
  // ajv cannot compile the full policy schema - an unrelated cron `pattern` in it is not a
  // valid unicode-mode regex - so validate against the `dependency_firewall_policy` subtree,
  // carrying `$defs` over for its `$ref`s. Strict mode is off because the schema declares
  // draft 2020-12 but still uses the draft-07 `additionalItems` keyword.
  const ajv = new Ajv({ strict: false, allowMatchingProperties: true });
  AjvFormats(ajv);
  const validate = ajv.compile({
    $schema: PolicySchema.$schema,
    $defs: PolicySchema.$defs,
    type: 'object',
    required: ['dependency_firewall_policy'],
    properties: {
      dependency_firewall_policy: PolicySchema.properties.dependency_firewall_policy,
    },
  });

  const parsed = () => safeLoad(DEFAULT_DEPENDENCY_FIREWALL_POLICY, { json: true });

  it('is intentionally invalid until a name and at least one rule are added', () => {
    // By design: an empty name and no rules guide the user to fill them in,
    // rather than showing pre-filled example data that looks real.
    // minLength/minItems in the schema surface that at save time.
    expect(parsed()).not.toValidateJsonSchema(validate);

    const policy = parsed().dependency_firewall_policy[0];
    expect(policy.name).toBe('');
    expect(policy.rules).toEqual([]);
  });

  it('rejects a rule that omits both denied and allowed', () => {
    const policy = parsed();
    policy.dependency_firewall_policy[0].name = 'A valid name';
    policy.dependency_firewall_policy[0].rules = [{ type: 'license' }];

    expect(policy).not.toValidateJsonSchema(validate);
  });

  it('validates a fully filled-in policy covering all four rule types', () => {
    const policy = parsed();
    const firstPolicy = policy.dependency_firewall_policy[0];

    firstPolicy.name = 'A fully configured policy';
    firstPolicy.description = 'Covers license, vulnerability, malicious, and risk_severity rules';
    firstPolicy.rules = [
      { ...buildDefaultRuleForType(RULE_TYPE_LICENSE), denied: [{ name: 'MIT' }] },
      buildDefaultRuleForType(RULE_TYPE_VULNERABILITY),
      buildDefaultRuleForType(RULE_TYPE_MALICIOUS),
      buildDefaultRuleForType(RULE_TYPE_RISK_SEVERITY),
    ];
    firstPolicy.bypass_settings = { users: [{ id: 1 }], access_tokens: [{ id: 2 }] };
    policy.dependency_firewall_policy[0] = removeIdsFromPolicy(firstPolicy);

    expect(policy).toValidateJsonSchema(validate);
  });
});
