<script>
import { GlFormInput } from '@gitlab/ui';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'TextListField',
  components: { FieldWrapper, GlFormInput },
  props: {
    field: {
      type: Object,
      required: true,
    },
    value: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['input'],
  computed: {
    display() {
      return this.value.join(', ');
    },
  },
  methods: {
    // The API persists these fields as string arrays. Splitting happens on
    // change (blur/enter) rather than per keystroke, or the normalization
    // would eat the separator the user just typed.
    updateList(raw) {
      const items = raw
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);

      this.$emit('input', items);
    },
  },
};
</script>

<template>
  <field-wrapper :field="field">
    <template #default="{ inputId }">
      <gl-form-input
        :id="inputId"
        :value="display"
        :placeholder="field.placeholder"
        @change="updateList"
      />
    </template>
  </field-wrapper>
</template>
