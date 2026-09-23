<script>
import { GlAlert, GlButton } from '@gitlab/ui';
import { s__ } from '~/locale';

const DEFAULT_TITLE = s__(
  'IdentityVerification|Before you can run pipelines, we need to verify your account.',
);
const DEFAULT_DESCRIPTION = s__(
  `IdentityVerification|We won't ask you for this information again. It will never be used for marketing purposes.`,
);
const DEFAULT_BUTTON_TEXT = s__('IdentityVerification|Verify my account');

export default {
  name: 'PipelineAccountVerificationAlert',
  components: { GlAlert, GlButton },
  inject: ['identityVerificationRequired', 'identityVerificationPath'],
  props: {
    title: {
      type: String,
      required: false,
      default: DEFAULT_TITLE,
    },
    description: {
      type: String,
      required: false,
      default: DEFAULT_DESCRIPTION,
    },
    buttonText: {
      type: String,
      required: false,
      default: DEFAULT_BUTTON_TEXT,
    },
    dismissible: {
      type: Boolean,
      required: false,
      default: true,
    },
    openInNewTab: {
      type: Boolean,
      required: false,
      default: false,
    },
    buttonVariant: {
      type: String,
      required: false,
      default: 'confirm',
    },
    sticky: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      isVisible: true,
    };
  },
  methods: {
    dismissAlert() {
      this.isVisible = false;
    },
  },
};
</script>

<template>
  <gl-alert
    v-if="identityVerificationRequired && isVisible"
    :title="title"
    :dismissible="dismissible"
    variant="danger"
    :sticky="sticky"
    @dismiss="dismissAlert"
  >
    {{ description }}
    <template #actions>
      <gl-button
        class="gl-alert-action"
        category="primary"
        :variant="buttonVariant"
        :href="identityVerificationPath"
        :target="openInNewTab ? '_blank' : undefined"
      >
        {{ buttonText }}
      </gl-button>
    </template>
  </gl-alert>
</template>
