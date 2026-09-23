import { GlFormRadioGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AllowDenyToggle from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/allow_deny_toggle.vue';

describe('AllowDenyToggle', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(AllowDenyToggle, {
      propsData: { listKey: 'denied', ...props },
    });
  };

  it('checks the radio matching listKey', () => {
    createWrapper({ listKey: 'allowed' });
    expect(wrapper.findComponent(GlFormRadioGroup).props('checked')).toBe('allowed');
  });

  it('emits change with the new key', () => {
    createWrapper();
    wrapper.findComponent(GlFormRadioGroup).vm.$emit('change', 'allowed');
    expect(wrapper.emitted('change')).toEqual([['allowed']]);
  });
});
