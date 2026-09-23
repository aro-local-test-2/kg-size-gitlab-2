import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RuleList from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_list.vue';
import RuleSection from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_section.vue';
import RuleTypeSelect from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_type_select.vue';

describe('RuleList', () => {
  let wrapper;

  const createWrapper = (rules = [{ type: 'license', denied: [] }], glFeatures = {}) => {
    wrapper = shallowMountExtended(RuleList, { propsData: { rules }, provide: { glFeatures } });
  };

  const findAddRuleSelect = () => wrapper.findComponent(RuleTypeSelect);

  it('renders one RuleSection per rule', () => {
    createWrapper([
      { type: 'license', denied: [] },
      { type: 'vulnerability', denied: [{ severity: 'high' }] },
    ]);
    expect(wrapper.findAllComponents(RuleSection)).toHaveLength(2);
  });

  it('shows an info alert and no rule cards when there are no rules', () => {
    createWrapper([]);
    expect(wrapper.findComponent(GlAlert).exists()).toBe(true);
    expect(wrapper.findComponent(RuleSection).exists()).toBe(false);
  });

  it('hides the info alert once at least one rule exists', () => {
    createWrapper([{ type: 'license', denied: [] }]);
    expect(wrapper.findComponent(GlAlert).exists()).toBe(false);
  });

  it('adds a fully-formed rule of the selected type', () => {
    createWrapper([]);
    findAddRuleSelect().vm.$emit('select', 'license');
    expect(wrapper.emitted('changed')[0][0]).toMatchObject([{ type: 'license', denied: [] }]);
  });

  it('disables the add-rule select at the max rule count', () => {
    createWrapper(new Array(5).fill({ type: 'license', denied: [] }));
    expect(findAddRuleSelect().props('disabled')).toBe(true);
  });

  it('does not disable the add-rule select below the max rule count', () => {
    createWrapper(new Array(4).fill({ type: 'license', denied: [] }));
    expect(findAddRuleSelect().props('disabled')).toBe(false);
  });

  it('removes a rule by index', () => {
    createWrapper([
      { type: 'license', denied: [] },
      { type: 'vulnerability', denied: [{ severity: 'high' }] },
    ]);
    wrapper.findAllComponents(RuleSection).at(0).vm.$emit('remove');
    expect(wrapper.emitted('changed')[0][0]).toEqual([
      { type: 'vulnerability', denied: [{ severity: 'high' }] },
    ]);
  });

  it('updates a rule by index', () => {
    createWrapper([{ type: 'license', denied: [] }]);
    wrapper
      .findComponent(RuleSection)
      .vm.$emit('changed', { type: 'license', denied: [{ name: 'MIT' }] });
    expect(wrapper.emitted('changed')[0][0]).toEqual([
      { type: 'license', denied: [{ name: 'MIT' }] },
    ]);
  });

  describe('when the risk_severity flag is off', () => {
    it('does not offer risk_severity in the add-rule select', () => {
      createWrapper([], { dependencyFirewallRiskSeverityRule: false });
      const values = findAddRuleSelect()
        .props('items')
        .map(({ value }) => value);
      expect(values).toContain('vulnerability');
      expect(values).not.toContain('risk_severity');
    });
  });

  describe('when the risk_severity flag is on', () => {
    it('offers risk_severity instead of vulnerability in the add-rule select', () => {
      createWrapper([], { dependencyFirewallRiskSeverityRule: true });
      const values = findAddRuleSelect()
        .props('items')
        .map(({ value }) => value);
      expect(values).toContain('risk_severity');
      expect(values).not.toContain('vulnerability');
    });
  });
});
