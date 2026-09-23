import { GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SeveritySelect from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/severity_select.vue';

describe('SeveritySelect', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(SeveritySelect, {
      propsData: { selected: 'high', ...props },
    });
  };

  it('passes the selected severity through', () => {
    createWrapper();
    expect(wrapper.findComponent(GlCollapsibleListbox).props('selected')).toBe('high');
  });

  it('emits select on choosing a severity', () => {
    createWrapper();
    wrapper.findComponent(GlCollapsibleListbox).vm.$emit('select', 'critical');
    expect(wrapper.emitted('select')).toEqual([['critical']]);
  });
});
