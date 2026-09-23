<script>
import { GlModal, GlSprintf } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { __ } from '~/locale';

export default {
  name: 'ArtifactRegistryDeleteConfirmationModal',
  components: {
    GlModal,
    GlSprintf,
  },
  model: {
    prop: 'target',
    event: 'change',
  },
  props: {
    target: {
      type: Object,
      required: false,
      default: null,
    },
    title: {
      type: String,
      required: true,
    },
    body: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: false,
      default: '',
    },
    actionText: {
      type: String,
      required: true,
    },
    modalId: {
      type: String,
      required: false,
      default: () => uniqueId('artifact-registry-delete-confirmation-modal-'),
    },
  },
  emits: ['change', 'confirm'],
  data() {
    return { copy: this.currentCopy() };
  },
  computed: {
    primaryAction() {
      return {
        text: this.copy.actionText,
        attributes: { variant: 'danger', category: 'primary' },
      };
    },
  },
  watch: {
    // Re-snapshot only when the modal opens. `data()` seeds the first snapshot, and holding
    // the last copy while `target` clears keeps the text from blanking during the close fade.
    target(target) {
      if (target) this.copy = this.currentCopy();
    },
  },
  methods: {
    currentCopy() {
      const { title, body, name, actionText } = this;

      return { title, body, name, actionText };
    },
    onChange(visible) {
      if (!visible) this.$emit('change', null);
    },
  },
  cancelAction: { text: __('Cancel') },
};
</script>

<template>
  <gl-modal
    :visible="Boolean(target)"
    :modal-id="modalId"
    :title="copy.title"
    :action-primary="primaryAction"
    :action-cancel="$options.cancelAction"
    size="sm"
    @primary="$emit('confirm', target)"
    @change="onChange"
  >
    <p class="gl-mb-0 gl-wrap-anywhere">
      <gl-sprintf :message="copy.body">
        <template #name>{{ copy.name }}</template>
      </gl-sprintf>
    </p>
  </gl-modal>
</template>
