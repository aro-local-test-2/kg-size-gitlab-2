<script>
import { GlAlert, GlModal } from '@gitlab/ui';
import { __, s__ } from '~/locale';

export default {
  name: 'SecretsManagerDisableModal',
  components: {
    GlAlert,
    GlModal,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    errorMessage: {
      type: String,
      required: false,
      default: '',
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    showTrialNote: {
      type: Boolean,
      required: false,
      default: true,
    },
    isInstance: {
      type: Boolean,
      required: false,
      default: false,
    },
    isOfflineLicense: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['unenroll', 'hide'],
  computed: {
    // Air-gapped instances are billed through their subscription, not
    // GitLab Credits.
    billingNote() {
      return this.isOfflineLicense
        ? s__('SecretsManager|GitLab Secrets Manager will no longer be billed when disabled.')
        : s__('SecretsManager|GitLab Secrets Manager will not use GitLab Credits when disabled.');
    },
    description() {
      return this.isInstance
        ? s__(
            'SecretsManager|This will disable GitLab Secrets Manager for all groups and projects in this instance.',
          )
        : s__(
            'SecretsManager|This will disable GitLab Secrets Manager for all groups and projects in this namespace.',
          );
    },
    actionPrimary() {
      return {
        text: s__('SecretsManager|Disable'),
        attributes: {
          variant: 'danger',
          loading: this.loading,
        },
      };
    },
    actionCancel() {
      return {
        text: __('Cancel'),
        attributes: {
          disabled: this.loading,
        },
      };
    },
  },
};
</script>
<template>
  <gl-modal
    modal-id="disable-secrets-manager-modal"
    :visible="visible"
    :title="s__('SecretsManager|Are you sure you want to disable GitLab Secrets Manager?')"
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    hide-header-close
    no-close-on-backdrop
    no-close-on-esc
    @primary.prevent="$emit('unenroll')"
    @hidden="$emit('hide')"
  >
    <gl-alert
      v-if="errorMessage"
      class="gl-mb-4"
      variant="danger"
      :dismissible="false"
      data-testid="disable-modal-error-alert"
    >
      {{ errorMessage }}
    </gl-alert>
    <p>{{ description }}</p>
    <ul>
      <li>{{ s__('SecretsManager|Jobs or workloads that fetch secrets will stop working.') }}</li>
      <li>
        {{
          s__(
            'SecretsManager|Project and group members will only be able to view details or delete existing secrets.',
          )
        }}
      </li>
      <li data-testid="disable-modal-billing-note">{{ billingNote }}</li>
    </ul>
    <p v-if="showTrialNote" data-testid="disable-modal-trial-note">
      {{
        s__(
          'SecretsManager|If you have started a free 30-day trial, you can re-enable GitLab Secrets Manager at any time before the end of your trial period.',
        )
      }}
    </p>
  </gl-modal>
</template>
