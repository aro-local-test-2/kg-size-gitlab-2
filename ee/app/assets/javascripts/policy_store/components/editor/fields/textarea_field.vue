<script>
import { GlFormTextarea } from '@gitlab/ui';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'TextareaField',
  components: { FieldWrapper, GlFormTextarea },
  props: {
    field: {
      type: Object,
      required: true,
    },
    value: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
};
</script>

<template>
  <field-wrapper :field="field">
    <template #default="{ inputId }">
      <gl-form-textarea
        :id="inputId"
        :value="value"
        :placeholder="field.placeholder"
        @input="$emit('input', $event)"
      />
    </template>
  </field-wrapper>
</template>
