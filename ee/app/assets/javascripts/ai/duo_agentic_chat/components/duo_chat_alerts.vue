<script>
import { GlAlert } from '@gitlab/ui';
import SafeHtml from '~/vue_shared/directives/safe_html';

// The chat's info and error banners. They outlive the header they used to be
// part of: under the redesign the header row is gone and these still render.
export default {
  name: 'DuoChatAlerts',
  components: {
    GlAlert,
  },
  directives: {
    SafeHtml,
  },
  props: {
    error: {
      type: String,
      required: false,
      default: '',
    },
    info: {
      type: String,
      required: false,
      default: '',
    },
  },
};
</script>

<template>
  <div data-testid="chat-alerts">
    <gl-alert
      v-if="info"
      key="info"
      :dismissible="false"
      variant="info"
      class="!gl-pl-9"
      role="alert"
      data-testid="chat-info"
    >
      <span v-safe-html="info"></span>
    </gl-alert>

    <gl-alert
      v-if="error"
      key="error"
      :dismissible="false"
      variant="danger"
      class="!gl-pl-9"
      role="alert"
      data-testid="chat-error"
    >
      <span v-safe-html="error"></span>
    </gl-alert>
  </div>
</template>
