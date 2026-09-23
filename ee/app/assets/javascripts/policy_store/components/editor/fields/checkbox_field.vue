<script>
import { GlFormCheckbox } from '@gitlab/ui';

export default {
  name: 'CheckboxField',
  components: { GlFormCheckbox },
  props: {
    field: {
      type: Object,
      required: true,
    },
    // `null` means "never touched" so `isChecked` can fall back to the catalog
    // default. Vue skips type validation for nullish values on non-required
    // props, so the Boolean constraint never fires on the null default.
    value: {
      type: Boolean,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  computed: {
    // GlFormCheckbox carries its own label, so this control does not use FieldWrapper.
    isChecked() {
      return this.value ?? this.field.default ?? false;
    },
  },
};
</script>

<template>
  <gl-form-checkbox :checked="isChecked" @change="$emit('input', $event)">
    {{ field.label }}
  </gl-form-checkbox>
</template>
