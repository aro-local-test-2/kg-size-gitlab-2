import { GlFormRadioGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnforcementTypeSelect from 'ee/security_orchestration/components/policy_editor/dependency_firewall/settings/enforcement_type_select.vue';

describe('EnforcementTypeSelect', () => {
  let wrapper;

  const createWrapper = (enforcementType = 'warn') => {
    wrapper = shallowMountExtended(EnforcementTypeSelect, {
      propsData: { enforcementType },
    });
  };

  it('checks the radio matching the current enforcement type', () => {
    createWrapper('enforced');
    expect(wrapper.findComponent(GlFormRadioGroup).props('checked')).toBe('enforced');
  });

  it('emits change with the new value', () => {
    createWrapper();
    wrapper.findComponent(GlFormRadioGroup).vm.$emit('change', 'enforced');
    expect(wrapper.emitted('change')).toEqual([['enforced']]);
  });
});
