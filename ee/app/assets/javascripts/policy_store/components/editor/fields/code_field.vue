<script>
import { GlButton, GlFormTextarea } from '@gitlab/ui';
import { s__ } from '~/locale';
import RegoTemplatesModal from '../rego_templates_modal.vue';
import FieldWrapper from './field_wrapper.vue';

export default {
  name: 'CodeField',
  components: { FieldWrapper, GlButton, GlFormTextarea, RegoTemplatesModal },
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
  i18n: {
    browseTemplates: s__('PolicyStore|Browse templates'),
  },
  data() {
    return { templatesVisible: false };
  },
};
</script>

<template>
  <field-wrapper :field="field">
    <template #label-actions>
      <gl-button
        category="secondary"
        variant="default"
        size="small"
        icon="documents"
        @click="templatesVisible = true"
      >
        {{ $options.i18n.browseTemplates }}
      </gl-button>
    </template>
    <template #default="{ inputId, labelTextId }">
      <gl-form-textarea
        :id="inputId"
        :aria-labelledby="labelTextId"
        :value="value"
        :placeholder="field.placeholder"
        :rows="10"
        :maxlength="field.maxLength"
        class="gl-border gl-rounded-lg gl-border-subtle gl-bg-subtle gl-font-monospace gl-text-sm"
        spellcheck="false"
        @input="$emit('input', $event)"
      />
      <rego-templates-modal
        :visible="templatesVisible"
        @select="$emit('input', $event)"
        @hide="templatesVisible = false"
      />
    </template>
  </field-wrapper>
</template>
