<script>
import { GlFormSelect } from '@gitlab/ui';
import { s__ } from '~/locale';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'SelectField',
  components: { FieldWrapper, GlFormSelect },
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
  computed: {
    placeholder() {
      return this.field.placeholder || s__('PolicyStore|Select...');
    },
  },
};
</script>

<template>
  <field-wrapper :field="field">
    <template #default="{ inputId }">
      <gl-form-select :id="inputId" :value="value" @change="$emit('input', $event)">
        <option value="">{{ placeholder }}</option>
        <option v-for="option in field.options" :key="option.id" :value="option.id">
          {{ option.label }}
        </option>
      </gl-form-select>
    </template>
  </field-wrapper>
</template>
