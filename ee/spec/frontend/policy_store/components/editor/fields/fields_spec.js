import {
  GlBadge,
  GlButton,
  GlFormCheckbox,
  GlFormGroup,
  GlFormInput,
  GlFormSelect,
  GlFormTextarea,
  GlIcon,
} from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CheckboxField from 'ee/policy_store/components/editor/fields/checkbox_field.vue';
import CodeField from 'ee/policy_store/components/editor/fields/code_field.vue';
import FieldWrapper from 'ee/policy_store/components/editor/fields/field_wrapper.vue';
import SelectField from 'ee/policy_store/components/editor/fields/select_field.vue';
import TextField from 'ee/policy_store/components/editor/fields/text_field.vue';
import TextListField from 'ee/policy_store/components/editor/fields/text_list_field.vue';
import TextareaField from 'ee/policy_store/components/editor/fields/textarea_field.vue';
import MultiBadgeSelector from 'ee/policy_store/components/editor/fields/multi_badge_selector.vue';
import RegoTemplatesModal from 'ee/policy_store/components/editor/rego_templates_modal.vue';

describe('editor field controls', () => {
  let wrapper;

  describe('FieldWrapper', () => {
    const mountWrapper = (field, props = {}) =>
      mountExtended(FieldWrapper, {
        propsData: { field, ...props },
        scopedSlots: { default: '<input :id="props.inputId" />' },
      });

    it('points the label at the control it labels', () => {
      wrapper = mountWrapper({ key: 'branch', label: 'Branch' });
      const inputId = wrapper.find('input').attributes('id');

      expect(wrapper.find('label').text()).toContain('Branch');
      expect(inputId).toMatch(/^policy-store-field-\d+$/);
      expect(wrapper.find('label').attributes('for')).toBe(inputId);
    });

    it('gives every instance its own id, so entries sharing a field key do not collide', () => {
      const first = mountWrapper({ key: 'policy', label: 'Rego' });
      const second = mountWrapper({ key: 'policy', label: 'Rego' });

      expect(first.find('input').attributes('id')).not.toBe(second.find('input').attributes('id'));
    });

    it('omits the label target when the slot holds a group of controls', () => {
      wrapper = shallowMountExtended(FieldWrapper, {
        propsData: { field: { key: 'branch', label: 'Branch' }, labelledControl: false },
      });

      expect(wrapper.findComponent(GlFormGroup).attributes('label-for')).toBeUndefined();
    });

    it('renders the description under the control', () => {
      wrapper = mountWrapper({ key: 'branch', label: 'Branch', description: 'Sub-text' });

      expect(wrapper.text()).toContain('Sub-text');
    });

    it('marks a required field with a semantic token rather than a raw colour', () => {
      wrapper = mountWrapper({ key: 'branch', label: 'Branch', required: true });

      expect(wrapper.findByTestId('required-marker').classes()).toContain('gl-text-danger');
    });

    it('renders slotted actions in a row beside the label text, outside its named span', () => {
      wrapper = mountExtended(FieldWrapper, {
        propsData: { field: { key: 'policy', label: 'Rego' } },
        slots: {
          default: '<textarea />',
          'label-actions': '<button data-testid="label-action">Browse</button>',
        },
      });
      const row = wrapper.findByTestId('label-row');

      expect(row.classes()).toEqual(
        expect.arrayContaining(['gl-flex', 'gl-items-center', 'gl-justify-between']),
      );
      expect(row.find('[data-testid="label-action"]').text()).toBe('Browse');
      expect(wrapper.find('label [data-testid="label-row"]').exists()).toBe(true);
      expect(wrapper.find('[id^="policy-store-field-label-"]').text()).toBe('Rego');
    });

    it('hands the control the id of the label text, so actions stay out of its name', () => {
      wrapper = mountExtended(FieldWrapper, {
        propsData: { field: { key: 'policy', label: 'Rego' } },
        scopedSlots: { default: '<input :aria-labelledby="props.labelTextId" />' },
      });
      const labelTextId = wrapper.find('input').attributes('aria-labelledby');

      expect(labelTextId).toMatch(/^policy-store-field-label-\d+$/);
      expect(wrapper.find(`#${labelTextId}`).text()).toBe('Rego');
    });

    it('renders a help icon only when the field declares help text', () => {
      expect(mountWrapper({ key: 'b', label: 'B' }).findComponent(GlIcon).exists()).toBe(false);
      expect(
        mountWrapper({ key: 'b', label: 'B', helpText: 'Why' }).findComponent(GlIcon).exists(),
      ).toBe(true);
    });
  });

  describe('TextField', () => {
    it('renders the value and placeholder, and emits on input', () => {
      wrapper = mountExtended(TextField, {
        propsData: {
          field: { key: 'branch', label: 'Branch', placeholder: 'e.g. main' },
          value: 'x',
        },
      });

      expect(wrapper.findComponent(GlFormInput).props('value')).toBe('x');
      expect(wrapper.find('input').attributes('placeholder')).toBe('e.g. main');
      expect(wrapper.find('input').attributes('id')).toMatch(/^policy-store-field-\d+$/);
      expect(wrapper.find('label').attributes('for')).toBe(wrapper.find('input').attributes('id'));

      wrapper.findComponent(GlFormInput).vm.$emit('input', 'main');
      expect(wrapper.emitted('input')).toEqual([['main']]);
    });
  });

  describe('TextListField', () => {
    const field = { key: 'names', label: 'Environment names' };
    const mountField = (value) =>
      mountExtended(TextListField, { propsData: { field, ...(value ? { value } : {}) } });

    it('displays the stored array as a comma-separated string', () => {
      wrapper = mountField(['production', 'staging']);

      expect(wrapper.findComponent(GlFormInput).props('value')).toBe('production, staging');
    });

    it('splits the input into a trimmed array on change, dropping empties', () => {
      wrapper = mountField();

      wrapper.findComponent(GlFormInput).vm.$emit('change', ' production ,, staging ,');

      expect(wrapper.emitted('input')).toEqual([[['production', 'staging']]]);
    });

    it('emits an empty array when the input is cleared', () => {
      wrapper = mountField(['production']);

      wrapper.findComponent(GlFormInput).vm.$emit('change', '');

      expect(wrapper.emitted('input')).toEqual([[[]]]);
    });
  });

  describe('TextareaField', () => {
    it('renders the value and emits on input', () => {
      wrapper = mountExtended(TextareaField, {
        propsData: { field: { key: 'message', label: 'Message' }, value: 'hi' },
      });

      expect(wrapper.findComponent(GlFormTextarea).props('value')).toBe('hi');
      expect(wrapper.find('textarea').attributes('id')).toMatch(/^policy-store-field-\d+$/);
      expect(wrapper.find('label').attributes('for')).toBe(
        wrapper.find('textarea').attributes('id'),
      );

      wrapper.findComponent(GlFormTextarea).vm.$emit('input', 'bye');
      expect(wrapper.emitted('input')).toEqual([['bye']]);
    });
  });

  describe('SelectField', () => {
    const field = {
      key: 'tier',
      label: 'Tier',
      options: [
        { id: 'production', label: 'Production' },
        { id: 'staging', label: 'Staging' },
      ],
    };

    it('renders a placeholder option followed by each option', () => {
      wrapper = mountExtended(SelectField, { propsData: { field } });

      expect(wrapper.findAll('option').wrappers.map((o) => o.text())).toEqual([
        'Select...',
        'Production',
        'Staging',
      ]);
      expect(wrapper.find('select').attributes('id')).toMatch(/^policy-store-field-\d+$/);
      expect(wrapper.find('label').attributes('for')).toBe(wrapper.find('select').attributes('id'));
    });

    it('uses the field placeholder for the empty option when given', () => {
      wrapper = mountExtended(SelectField, {
        propsData: { field: { ...field, placeholder: 'Any tier' } },
      });

      expect(wrapper.findAll('option').at(0).text()).toBe('Any tier');
    });

    it('emits on change', () => {
      wrapper = mountExtended(SelectField, { propsData: { field } });

      wrapper.findComponent(GlFormSelect).vm.$emit('change', 'staging');
      expect(wrapper.emitted('input')).toEqual([['staging']]);
    });
  });

  describe('CheckboxField', () => {
    const field = { key: 'sameRef', label: 'Same ref' };
    const create = (props) =>
      shallowMountExtended(CheckboxField, { propsData: { field, ...props } });

    it('labels itself from the field', () => {
      expect(create().findComponent(GlFormCheckbox).text()).toBe('Same ref');
    });

    it('is unchecked when neither a value nor a default is set', () => {
      expect(create().findComponent(GlFormCheckbox).props('checked')).toBe(false);
    });

    it('falls back to the field default', () => {
      wrapper = shallowMountExtended(CheckboxField, {
        propsData: { field: { ...field, default: true } },
      });

      expect(wrapper.findComponent(GlFormCheckbox).props('checked')).toBe(true);
    });

    it('prefers an explicit false value over a true default', () => {
      wrapper = shallowMountExtended(CheckboxField, {
        propsData: { field: { ...field, default: true }, value: false },
      });

      expect(wrapper.findComponent(GlFormCheckbox).props('checked')).toBe(false);
    });

    it('emits on change', () => {
      wrapper = create();

      wrapper.findComponent(GlFormCheckbox).vm.$emit('change', true);
      expect(wrapper.emitted('input')).toEqual([[true]]);
    });
  });

  describe('CodeField', () => {
    const field = { key: 'policy', label: 'Rego policy definition', maxLength: 32768 };
    // Full mount: the editor and its button live in FieldWrapper's slots, which a stub drops.
    const create = (props) => mountExtended(CodeField, { propsData: { field, ...props } });

    it('renders the field description through FieldWrapper', () => {
      wrapper = create({ field: { ...field, description: 'Evaluated on every deployment' } });

      expect(wrapper.findComponent(FieldWrapper).props('field').description).toBe(
        'Evaluated on every deployment',
      );
      expect(wrapper.text()).toContain('Evaluated on every deployment');
    });

    it('renders a monospace editor honouring the field constraints', () => {
      wrapper = create({ value: 'package foo' });
      const textarea = wrapper.findComponent(GlFormTextarea);

      expect(textarea.props('value')).toBe('package foo');
      expect(textarea.attributes('maxlength')).toBe('32768');
      expect(textarea.attributes('spellcheck')).toBe('false');
      expect(textarea.classes()).toContain('gl-font-monospace');
    });

    it('ties its label to the editor and names it by the label text alone', () => {
      wrapper = create();
      const textarea = wrapper.find('textarea');
      const labelTextId = textarea.attributes('aria-labelledby');

      expect(wrapper.findAll('label')).toHaveLength(1);
      expect(textarea.attributes('id')).toMatch(/^policy-store-field-\d+$/);
      expect(wrapper.find('label').attributes('for')).toBe(textarea.attributes('id'));
      expect(wrapper.find(`#${labelTextId}`).text()).toBe('Rego policy definition');
      expect(wrapper.find('label').text()).toContain('Browse templates');
    });

    it('opens the templates modal from the browse button and applies a choice', async () => {
      wrapper = create();
      expect(wrapper.findComponent(RegoTemplatesModal).props('visible')).toBe(false);

      await wrapper.findComponent(GlButton).vm.$emit('click');
      expect(wrapper.findComponent(RegoTemplatesModal).props('visible')).toBe(true);

      wrapper.findComponent(RegoTemplatesModal).vm.$emit('select', 'package governance');
      expect(wrapper.emitted('input')).toEqual([['package governance']]);
    });

    it('emits on input', () => {
      wrapper = create();

      wrapper.findComponent(GlFormTextarea).vm.$emit('input', 'package bar');
      expect(wrapper.emitted('input')).toEqual([['package bar']]);
    });
  });

  describe('MultiBadgeSelector', () => {
    const field = {
      key: 'roles',
      label: 'Role approvers',
      options: [
        { id: 'a', label: 'Alpha' },
        { id: 'b', label: 'Beta' },
      ],
    };
    const create = (props) =>
      shallowMountExtended(MultiBadgeSelector, { propsData: { field, ...props } });
    const findBadges = () => wrapper.findAllComponents(GlBadge);

    it('renders each option as a button, since they are meant to be interacted with', () => {
      wrapper = create();

      expect(findBadges().wrappers.map((b) => b.text())).toEqual(['Alpha', 'Beta']);
      expect(findBadges().wrappers.every((b) => b.props('tag') === 'button')).toBe(true);
    });

    it('names the group once, through the fieldset legend rather than a nested group', () => {
      wrapper = mountExtended(MultiBadgeSelector, { propsData: { field } });

      expect(wrapper.findComponent(FieldWrapper).props('labelledControl')).toBe(false);
      expect(wrapper.findAll('legend')).toHaveLength(1);
      expect(wrapper.find('fieldset legend').text()).toContain('Role approvers');
      expect(wrapper.find('[role="group"]').exists()).toBe(false);
      expect(wrapper.find('div[aria-label]').exists()).toBe(false);
    });

    it('announces the pressed state of every option, selected or not', () => {
      wrapper = create({ value: ['a'] });

      expect(findBadges().wrappers.map((b) => b.attributes('aria-pressed'))).toEqual([
        'true',
        'false',
      ]);
    });

    it('adds and removes options as they are clicked', () => {
      wrapper = create({ value: ['a'] });

      findBadges().at(1).vm.$emit('click');
      expect(wrapper.emitted('input')).toEqual([[['a', 'b']]]);

      findBadges().at(0).vm.$emit('click');
      expect(wrapper.emitted('input')[1]).toEqual([['a'].filter((id) => id !== 'a')]);
    });
  });
});
