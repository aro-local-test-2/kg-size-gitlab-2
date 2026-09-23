import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import LicenseRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/license_rule_builder.vue';
import RuleMultiSelect from 'ee/security_orchestration/components/policy_editor/rule_multi_select.vue';
import NameListTextarea from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/name_list_textarea.vue';

const PARSED_SOFTWARE_LICENSES = [
  { value: 'MIT', text: 'MIT' },
  { value: 'GPL-3.0', text: 'GPL-3.0' },
];

describe('LicenseRuleBuilder', () => {
  let wrapper;

  const createWrapper = (initRule = { type: 'license', denied: [{ name: 'MIT' }] }) => {
    wrapper = shallowMountExtended(LicenseRuleBuilder, {
      propsData: { initRule },
      provide: { parsedSoftwareLicenses: PARSED_SOFTWARE_LICENSES },
    });
  };

  const findNamesInput = () => wrapper.findComponent(RuleMultiSelect);
  const findExceptionsInput = () => wrapper.findComponent(NameListTextarea);
  const findAlert = () => wrapper.findComponent(GlAlert);

  it('does not render an allow-list alert for a deny rule', () => {
    createWrapper();
    expect(findAlert().exists()).toBe(false);
  });

  it('renders an allow-list alert for a legacy allow rule', () => {
    createWrapper({ type: 'license', allowed: [{ name: 'MIT' }] });
    expect(findAlert().exists()).toBe(true);
  });

  it('passes the current names and the known license catalogue to the multi-select', () => {
    createWrapper();
    expect(findNamesInput().props('value')).toEqual(['MIT']);
    expect(findNamesInput().props('items')).toEqual({ MIT: 'MIT', 'GPL-3.0': 'GPL-3.0' });
    expect(findNamesInput().props('searchable')).toBe(true);
  });

  describe('when names change', () => {
    beforeEach(() => {
      createWrapper();
      findNamesInput().vm.$emit('input', ['MIT', 'GPL-3.0']);
    });

    it('emits changed with an updated denied list', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'license',
        denied: [{ name: 'MIT' }, { name: 'GPL-3.0' }],
      });
    });
  });

  describe('when the exceptions input changes', () => {
    beforeEach(() => {
      createWrapper();
      findExceptionsInput().vm.$emit('input', ['pkg:npm/lodash@4.17.21']);
    });

    it('emits changed with exceptions', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'license',
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
    });
  });

  describe('when exceptions are cleared', () => {
    beforeEach(() => {
      createWrapper({
        type: 'license',
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
      findExceptionsInput().vm.$emit('input', []);
    });

    it('emits changed with the exceptions key removed', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'license',
        denied: [{ name: 'MIT' }],
      });
      expect(wrapper.emitted('changed')[0][0]).not.toHaveProperty('exceptions');
    });
  });
});
