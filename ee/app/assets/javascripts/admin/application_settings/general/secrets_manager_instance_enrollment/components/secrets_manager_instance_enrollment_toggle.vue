<script>
import { GlAlert, GlToggle, GlToastMixin } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { logError } from '~/lib/logger';
import { s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import SecretsManagerDisableModal from 'ee/ci/secrets/components/secrets_manager_disable_modal.vue';
import enrollInstanceSecretsManagerMutation from '../graphql/mutations/enroll_instance_secrets_manager.mutation.graphql';
import unenrollInstanceSecretsManagerMutation from '../graphql/mutations/unenroll_instance_secrets_manager.mutation.graphql';

export default {
  name: 'SecretsManagerInstanceEnrollmentToggle',
  components: {
    GlAlert,
    GlToggle,
    SecretsManagerDisableModal,
  },
  i18n: {
    updateError: s__('SecretsManager|Failed to update Secrets Manager enrollment.'),
    enrollSuccess: s__('SecretsManager|Secrets Manager is enabled.'),
    unenrollSuccess: s__('SecretsManager|Secrets Manager is disabled.'),
  },
  mixins: [glFeatureFlagsMixin(), GlToastMixin],
  props: {
    isEnrolled: {
      type: Boolean,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
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
    isOfflineLicense: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['toggled'],
  data() {
    return {
      errorMessage: '',
      isMutating: false,
      modalErrorMessage: '',
      showDisableModal: false,
    };
  },
  computed: {
    isLoading() {
      return this.loading || this.isMutating;
    },
    showPaidExperience() {
      return this.glFeatures.secretsManagerPaidExperience;
    },
  },
  methods: {
    reportError(message, error) {
      if (this.showDisableModal) {
        this.modalErrorMessage = message;
      } else {
        this.errorMessage = message;
      }

      logError(message, error);
      Sentry.captureException(error);
    },
    toggleEnrollment(shouldEnroll) {
      if (shouldEnroll) {
        return this.enroll();
      }

      if (this.showPaidExperience) {
        this.showDisableModal = true;
        return undefined;
      }

      return this.unenroll();
    },
    enroll() {
      return this.performMutation({
        mutation: enrollInstanceSecretsManagerMutation,
        responseKey: 'instanceSecretsManagerEnroll',
        nextValue: true,
        successMessage: this.$options.i18n.enrollSuccess,
      });
    },
    unenroll() {
      return this.performMutation({
        mutation: unenrollInstanceSecretsManagerMutation,
        responseKey: 'instanceSecretsManagerUnenroll',
        nextValue: false,
        successMessage: this.$options.i18n.unenrollSuccess,
      });
    },
    async performMutation({ mutation, responseKey, nextValue, successMessage }) {
      this.isMutating = true;
      this.errorMessage = '';
      this.modalErrorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation,
          context: { featureCategory: 'secrets_management' },
        });
        const errors = data?.[responseKey]?.errors ?? [];

        if (errors.length) {
          throw new Error(errors.join(', '));
        }

        this.showDisableModal = false;
        this.$toast.show(successMessage);
        this.$emit('toggled', nextValue);
      } catch (error) {
        this.reportError(this.$options.i18n.updateError, error);
      } finally {
        this.isMutating = false;
      }
    },
    hideDisableModal() {
      this.showDisableModal = false;
      this.modalErrorMessage = '';
    },
  },
};
</script>
<template>
  <div>
    <gl-alert
      v-if="errorMessage"
      class="gl-mb-4"
      variant="danger"
      data-testid="enrollment-error-alert"
      @dismiss="errorMessage = ''"
    >
      {{ errorMessage }}
    </gl-alert>
    <gl-toggle
      :value="isEnrolled"
      :disabled="isLoading || disabled"
      :is-loading="isLoading"
      :label="s__('SecretsManager|Secrets Manager')"
      label-position="hidden"
      data-testid="secrets-manager-instance-enrollment-toggle"
      @change="toggleEnrollment"
    />
    <secrets-manager-disable-modal
      :visible="showDisableModal"
      :loading="isMutating"
      :show-trial-note="showTrialNote"
      :error-message="modalErrorMessage"
      :is-offline-license="isOfflineLicense"
      is-instance
      @unenroll="unenroll"
      @hide="hideDisableModal"
    />
  </div>
</template>
