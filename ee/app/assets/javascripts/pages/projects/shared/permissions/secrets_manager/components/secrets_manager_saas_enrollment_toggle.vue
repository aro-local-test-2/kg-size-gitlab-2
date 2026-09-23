<script>
import { GlLink, GlToggle, GlToastMixin } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import enrollMutation from 'ee/ci/secrets/graphql/mutations/enroll_namespace_secrets_manager.mutation.graphql';
import SecretsManagerDisableModal from 'ee/ci/secrets/components/secrets_manager_disable_modal.vue';
import unenrollMutation from '../graphql/unenroll_namespace_secrets_manager.mutation.graphql';

export default {
  name: 'SecretsManagerSaasEnrollmentToggle',
  components: {
    GlLink,
    GlToggle,
    SecretsManagerDisableModal,
  },
  mixins: [glFeatureFlagsMixin(), GlToastMixin],
  props: {
    canManageEnrollment: {
      type: Boolean,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: true,
    },
    fullPath: {
      type: String,
      required: true,
    },
    hasEnrollmentQueryError: {
      type: Boolean,
      required: true,
    },
    hideInlineText: {
      type: Boolean,
      required: false,
      default: false,
    },
    isEnrolled: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['toggled'],
  data() {
    return {
      errorMessage: null,
      isLoading: false,
      modalErrorMessage: '',
      showDisableModal: false,
    };
  },
  computed: {
    isToggleDisabled() {
      return (
        !this.canManageEnrollment ||
        this.hasEnrollmentQueryError ||
        this.isLoading ||
        (this.showPaidExperience && this.disabled)
      );
    },
    showPaidExperience() {
      return this.glFeatures.secretsManagerPaidExperience;
    },
  },
  methods: {
    async enrollNamespace() {
      this.isLoading = true;
      this.errorMessage = null;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: enrollMutation,
          variables: { fullPath: this.fullPath },
          context: { featureCategory: 'secrets_management' },
        });

        const { errors } = data.namespaceSecretsManagerEnroll;

        if (errors.length > 0) {
          throw new Error(errors[0]);
        }

        this.$emit('toggled');
        this.$toast.show(
          s__('SecretsManagerPermissions|GitLab Secrets Manager is enabled for this namespace.'),
        );
      } catch (error) {
        this.errorMessage =
          error.message ||
          s__(
            'SecretsManagerPermissions|There was a problem enabling GitLab Secrets Manager. Please try again.',
          );
        Sentry.captureException(error);
      } finally {
        this.isLoading = false;
      }
    },
    callMutation() {
      if (!this.isEnrolled) {
        this.enrollNamespace();
      } else if (this.showPaidExperience) {
        this.showDisableModal = true;
      } else {
        this.unenrollNamespace();
      }
    },
    async unenrollNamespace() {
      this.isLoading = true;
      this.errorMessage = null;
      this.modalErrorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: unenrollMutation,
          variables: { fullPath: this.fullPath },
          context: { featureCategory: 'secrets_management' },
        });

        const { errors } = data.namespaceSecretsManagerUnenroll;

        if (errors.length > 0) {
          throw new Error(errors[0]);
        }

        this.showDisableModal = false;
        this.$emit('toggled');
        this.$toast.show(
          s__('SecretsManagerPermissions|GitLab Secrets Manager is disabled for this namespace.'),
        );
      } catch (error) {
        const message =
          error.message ||
          s__(
            'SecretsManagerPermissions|There was a problem disabling GitLab Secrets Manager. Please try again.',
          );

        if (this.showDisableModal) {
          this.modalErrorMessage = message;
        } else {
          this.errorMessage = message;
        }

        Sentry.captureException(error);
      } finally {
        this.isLoading = false;
      }
    },
    hideDisableModal() {
      this.showDisableModal = false;
      this.modalErrorMessage = '';
    },
  },
  LEARN_MORE_LINK: helpPagePath('ci/secrets/secrets_manager/_index'),
};
</script>

<template>
  <div>
    <template v-if="!hideInlineText">
      <label class="gl-mb-1" for="gsm-enrollment-toggle">
        {{ s__('SecretsManagerPermissions|GitLab Secrets Manager') }}
      </label>
      <p class="gl-mb-2 gl-text-subtle">
        {{
          s__(
            'SecretsManagerPermissions|Allow the secrets manager to be enabled in any project or subgroup in this group.',
          )
        }}
        <gl-link :href="$options.LEARN_MORE_LINK">
          {{ __('Learn more.') }}
        </gl-link>
      </p>
    </template>
    <gl-toggle
      id="gsm-enrollment-toggle"
      :value="isEnrolled"
      :label="s__('SecretsManagerPermissions|GitLab Secrets Manager')"
      :disabled="isToggleDisabled"
      :is-loading="isLoading"
      data-testid="gsm-enrollment-toggle"
      label-position="hidden"
      name="gsm-enrollment-toggle"
      @change="callMutation"
    />
    <p
      v-if="errorMessage"
      class="gl-mb-0 gl-mt-2 gl-text-danger"
      data-testid="gsm-enrollment-error"
    >
      {{ errorMessage }}
    </p>
    <secrets-manager-disable-modal
      :visible="showDisableModal"
      :loading="isLoading"
      :error-message="modalErrorMessage"
      @unenroll="unenrollNamespace"
      @hide="hideDisableModal"
    />
  </div>
</template>
