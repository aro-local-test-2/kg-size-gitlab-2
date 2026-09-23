<script>
import { GlButton, GlFormCheckbox, GlModal, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import { GITLAB_DEFAULT_MODEL, SUPPRESS_DEFAULT_MODEL_MODAL_KEY } from './constants';

export default {
  name: 'GitlabDefaultModelModal',
  components: {
    GlButton,
    GlFormCheckbox,
    GlModal,
    GlSprintf,
  },
  props: {
    isAutoOption: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['confirm-submit'],
  data() {
    return {
      suppressModal: false,
    };
  },
  computed: {
    modalTitle() {
      return this.isAutoOption
        ? s__('ModelSelection|GitLab automatic routing')
        : s__('ModelSelection|GitLab default model');
    },
    primaryMessage() {
      return this.isAutoOption
        ? s__(
            'ModelSelection|When you select %{boldStart}Auto%{boldEnd}, GitLab routes each request to the most suitable model based on the task at hand.',
          )
        : s__(
            'ModelSelection|When you select the GitLab default model, GitLab uses the current default model for this feature. This model is updated automatically.',
          );
    },
    secondaryMessage() {
      return s__('ModelSelection|Alternatively, you can select a specific model to use.');
    },
  },
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- Invoked by parent component
    showModal() {
      this.$refs.modal.show();
    },
    hideModal() {
      this.$refs.modal.hide();
    },
    confirmSubmit() {
      this.$emit('confirm-submit', GITLAB_DEFAULT_MODEL);
    },
    onSubmit() {
      if (this.suppressModal) {
        localStorage.setItem(SUPPRESS_DEFAULT_MODEL_MODAL_KEY, 'true');
      }

      this.confirmSubmit();
      this.hideModal();
    },
  },
};
</script>
<template>
  <gl-modal ref="modal" modal-id="default-model-modal" :title="modalTitle">
    <template #default>
      <p>
        <gl-sprintf :message="primaryMessage">
          <template #bold="{ content }">
            <span class="gl-font-bold">{{ content }}</span>
          </template>
        </gl-sprintf>
      </p>
      <p>{{ secondaryMessage }}</p>
    </template>
    <template #modal-footer>
      <div class="gl-flex gl-items-baseline">
        <gl-form-checkbox v-model="suppressModal" class="gl-mr-5">
          {{ __('Do not show again') }}
        </gl-form-checkbox>
        <div>
          <gl-button data-testid="cancel-button" @click="hideModal">
            {{ __('Cancel') }}
          </gl-button>
          <gl-button data-testid="confirm-button" type="submit" variant="confirm" @click="onSubmit">
            {{ __('Confirm') }}
          </gl-button>
        </div>
      </div>
    </template>
  </gl-modal>
</template>
