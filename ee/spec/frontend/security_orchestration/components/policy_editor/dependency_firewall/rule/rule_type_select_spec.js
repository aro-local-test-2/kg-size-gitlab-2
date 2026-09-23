import { GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RuleTypeSelect from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_type_select.vue';

describe('RuleTypeSelect', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(RuleTypeSelect, { propsData: props });
  };

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);

  it('defaults to offering the three built-in rule types', () => {
    createWrapper();
    expect(findListbox().props('items')).toEqual([
      { value: 'license', text: 'License' },
      { value: 'vulnerability', text: 'Vulnerability' },
      { value: 'malicious', text: 'Malicious package' },
    ]);
  });

  it('uses the given items when provided', () => {
    const items = [{ value: 'risk_severity', text: 'Risk severity' }];
    createWrapper({ items });
    expect(findListbox().props('items')).toEqual(items);
  });

  it('falls back to the default header text when no toggleText is given', () => {
    createWrapper();
    expect(findListbox().props('toggleText')).toBe('Choose a rule type');
  });

  it('uses the given toggleText when provided', () => {
    createWrapper({ toggleText: 'Add new rule' });
    expect(findListbox().props('toggleText')).toBe('Add new rule');
  });

  it('is not disabled by default', () => {
    createWrapper();
    expect(findListbox().props('disabled')).toBe(false);
  });

  it('passes through the disabled prop', () => {
    createWrapper({ disabled: true });
    expect(findListbox().props('disabled')).toBe(true);
  });

  it('emits select with the chosen type', () => {
    createWrapper();
    findListbox().vm.$emit('select', 'vulnerability');
    expect(wrapper.emitted('select')).toEqual([['vulnerability']]);
  });
});
