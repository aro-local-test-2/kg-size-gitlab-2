import { GlFormTextarea } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import NameListTextarea from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/name_list_textarea.vue';

describe('NameListTextarea', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(NameListTextarea, {
      propsData: { items: [], placeholder: 'Add a name', ...props },
    });
  };

  const findTextarea = () => wrapper.findComponent(GlFormTextarea);

  it('renders the current items joined by newlines', () => {
    createWrapper({ items: ['MIT', 'GPL-3.0'] });
    expect(findTextarea().props('value')).toBe('MIT\nGPL-3.0');
  });

  describe('when wrapper is empty', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('emits input with a trimmed, deduplicated, non-empty array on change', () => {
      findTextarea().vm.$emit('input', 'MIT, GPL-3.0\n\nMIT ');
      expect(wrapper.emitted('input')).toEqual([[['MIT', 'GPL-3.0']]]);
    });

    it('does not clobber in-progress typing when the parent echoes the emitted items back', async () => {
      findTextarea().vm.$emit('input', 'MIT, ');
      await wrapper.setProps({ items: ['MIT'] });

      expect(findTextarea().props('value')).toBe('MIT, ');
    });
  });
});
