import { shallowMount } from '@vue/test-utils';
import ConfigWrapper from 'ee/policy_store/components/editor/config_wrapper.vue';
import { FIELD_TYPES } from 'ee/policy_store/components/editor/constants';
import FreezeWindowsConfig from 'ee/policy_store/components/editor/freeze_windows_config.vue';
import MultiBadgeSelector from 'ee/policy_store/components/editor/fields/multi_badge_selector.vue';
import CheckboxField from 'ee/policy_store/components/editor/fields/checkbox_field.vue';
import CodeField from 'ee/policy_store/components/editor/fields/code_field.vue';
import SelectField from 'ee/policy_store/components/editor/fields/select_field.vue';
import TextField from 'ee/policy_store/components/editor/fields/text_field.vue';
import TextListField from 'ee/policy_store/components/editor/fields/text_list_field.vue';
import TextareaField from 'ee/policy_store/components/editor/fields/textarea_field.vue';

describe('ConfigWrapper', () => {
  let wrapper;

  const createComponent = ({ fields = [], value = {} } = {}) => {
    wrapper = shallowMount(ConfigWrapper, { propsData: { fields, value } });
  };

  describe('dispatch', () => {
    it.each`
      type                | component
      ${'text'}           | ${TextField}
      ${'text_list'}      | ${TextListField}
      ${'textarea'}       | ${TextareaField}
      ${'select'}         | ${SelectField}
      ${'checkbox'}       | ${CheckboxField}
      ${'multi_badge'}    | ${MultiBadgeSelector}
      ${'code'}           | ${CodeField}
      ${'freeze_windows'} | ${FreezeWindowsConfig}
    `('renders the control registered for type $type', ({ type, component }) => {
      createComponent({ fields: [{ key: 'f', type, label: 'F', options: [] }] });

      expect(wrapper.findComponent(component).exists()).toBe(true);
    });

    // catalog_spec only checks catalog types against FIELD_TYPES; rendering is decided by
    // the component map, so a type present in one but not the other must fail here.
    it.each(FIELD_TYPES)('registers a control for the declared type %s', (type) => {
      createComponent({ fields: [{ key: 'f', type, label: 'F', options: [] }] });

      expect(wrapper.find('*').element.children).toHaveLength(1);
    });

    it('renders nothing for a type it has no control for, rather than guessing', () => {
      createComponent({ fields: [{ key: 'f', type: 'named_checkbox_grid', label: 'F' }] });

      expect(wrapper.findComponent(TextField).exists()).toBe(false);
      expect(wrapper.find('*').element.children).toHaveLength(0);
    });

    it('gives each control only its own slice of the value', () => {
      createComponent({
        fields: [
          { key: 'a', type: 'text', label: 'A' },
          { key: 'b', type: 'textarea', label: 'B' },
        ],
        value: { a: 'first', b: 'second' },
      });

      expect(wrapper.findComponent(TextField).props('value')).toBe('first');
      expect(wrapper.findComponent(TextareaField).props('value')).toBe('second');
    });

    it('renders nothing when there are no fields', () => {
      createComponent({ fields: [] });

      expect(wrapper.find('*').element.children).toHaveLength(0);
    });
  });

  describe('merging', () => {
    it('merges a control emission into the full value object', () => {
      createComponent({
        fields: [{ key: 'branch', type: 'text', label: 'Branch' }],
        value: { existing: 'kept' },
      });

      wrapper.findComponent(TextField).vm.$emit('input', 'main');

      expect(wrapper.emitted('input')).toEqual([[{ existing: 'kept', branch: 'main' }]]);
    });
  });

  describe('defaults', () => {
    it('seeds every field declaring a default in a single update', () => {
      createComponent({
        fields: [
          { key: 'policy', type: 'code', label: 'Rego', default: 'package foo' },
          { key: 'denyUnlisted', type: 'checkbox', label: 'Deny unlisted', default: true },
          { key: 'branch', type: 'text', label: 'Branch' },
        ],
      });

      expect(wrapper.emitted('input')).toEqual([[{ policy: 'package foo', denyUnlisted: true }]]);
    });

    it('keeps values already set rather than overwriting them with the default', () => {
      createComponent({
        fields: [{ key: 'denyUnlisted', type: 'checkbox', label: 'Deny', default: true }],
        value: { denyUnlisted: false },
      });

      expect(wrapper.emitted('input')).toBeUndefined();
    });

    it('seeds a default of false, which is a value rather than an absent one', () => {
      createComponent({
        fields: [{ key: 'denyUnlisted', type: 'checkbox', label: 'Deny', default: false }],
      });

      expect(wrapper.emitted('input')).toEqual([[{ denyUnlisted: false }]]);
    });

    it('emits nothing when no field declares a default', () => {
      createComponent({ fields: [{ key: 'branch', type: 'text', label: 'Branch' }] });

      expect(wrapper.emitted('input')).toBeUndefined();
    });
  });
});
