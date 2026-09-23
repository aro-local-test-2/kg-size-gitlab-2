<script>
import { GlAlert, GlLink, GlSkeletonLoader, GlToggle, GlToastMixin } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import {
  ACTION_ENABLE_SECRET_MANAGER,
  ACTION_DISABLE_SECRET_MANAGER,
  SECRET_MANAGER_STATUS_ACTIVE,
  SECRET_MANAGER_STATUS_INACTIVE,
  SECRET_MANAGER_STATUS_PROVISIONING,
  SECRET_MANAGER_STATUS_DEPROVISIONING,
  ENTITY_PROJECT,
  ENTITY_GROUP,
} from 'ee/ci/secrets/constants';
import SecretsManagerBillingAlert from 'ee/ci/secrets/components/secrets_manager_billing_alert.vue';
import {
  hasSelectedTrialOrPaidAddOn,
  isProvisioningBlockedByEntitlement,
} from 'ee/ci/secrets/utils';
import getOpenbaoHealthQuery from 'ee/ci/secrets/graphql/queries/get_openbao_health.query.graphql';
import getEntitlementQuery from 'ee/ci/secrets/graphql/queries/get_secrets_manager_entitlement.graphql';
import { SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG } from './context_config';
import getEnrollment from './graphql/get_gsm_namespace_enrollment.query.graphql';
import PermissionsSettings from './components/secrets_manager_permissions_settings.vue';
import SaasEnrollmentToggle from './components/secrets_manager_saas_enrollment_toggle.vue';

export const POLL_INTERVAL = 2000;

const PROVISIONED_MESSAGES = {
  [ENTITY_PROJECT]: s__(
    'SecretsManagerPermissions|GitLab Secrets Manager has been provisioned for this project.',
  ),
  [ENTITY_GROUP]: s__(
    'SecretsManagerPermissions|GitLab Secrets Manager has been provisioned for this group.',
  ),
};

const DEPROVISIONED_MESSAGES = {
  [ENTITY_PROJECT]: s__(
    'SecretsManagerPermissions|GitLab Secrets Manager has been deprovisioned for this project.',
  ),
  [ENTITY_GROUP]: s__(
    'SecretsManagerPermissions|GitLab Secrets Manager has been deprovisioned for this group.',
  ),
};

const DESCRIPTION_MESSAGES = {
  [ENTITY_PROJECT]: s__(
    'SecretsManagerPermissions|Store secrets in the secrets manager, which can then be fetched by this project.',
  ),
  [ENTITY_GROUP]: s__(
    'SecretsManagerPermissions|Store secrets in the secrets manager, which can then be fetched by any project in this group and its subgroups.',
  ),
};

export default {
  name: 'SecretsManagerSettings',
  components: {
    GlAlert,
    GlLink,
    GlSkeletonLoader,
    GlToggle,
    PermissionsSettings,
    SaasEnrollmentToggle,
    SecretsManagerBillingAlert,
  },
  mixins: [glFeatureFlagsMixin(), GlToastMixin],
  props: {
    canEnrollNamespace: {
      type: Boolean,
      required: true,
    },
    canManageSecretsManager: {
      type: Boolean,
      required: true,
    },
    context: {
      type: String,
      required: true,
    },
    fullPath: {
      type: String,
      required: true,
    },
    // Inside the standalone settings block (the group Secure tab) the block
    // supplies the heading and description, so the component's own inline
    // title/label/description are suppressed to avoid duplication.
    hideInlineText: {
      type: Boolean,
      required: false,
      default: false,
    },
    isNamespaceEnrollable: {
      type: Boolean,
      required: false,
      default: false,
    },
    topLevelGroupFullPath: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      action: null,
      entitlement: null,
      errorMessage: '',
      hasEnrollmentQueryError: false,
      isEnrolled: false,
      isOpenbaoHealthy: true,
      secretManagerStatus: SECRET_MANAGER_STATUS_INACTIVE,
    };
  },
  computed: {
    contextConfig() {
      return SECRETS_MANAGER_PERMISSIONS_CONTEXT_CONFIG[this.context];
    },
    isActive() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_ACTIVE;
    },
    isEnablingSecretsManager() {
      return this.action === ACTION_ENABLE_SECRET_MANAGER;
    },
    isDisablingSecretsManager() {
      return this.action === ACTION_DISABLE_SECRET_MANAGER;
    },
    isEnrollableAndNotEnrolled() {
      return this.isNamespaceEnrollable && !this.isEnrolled;
    },
    isBlockedByEntitlement() {
      return this.showPaidExperience && isProvisioningBlockedByEntitlement(this.entitlement);
    },
    isInactive() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_INACTIVE;
    },
    isLoadingEnrollment() {
      return this.$apollo.queries.isEnrolled.loading;
    },
    // Only relevant in the paid experience, where the entitlement decides
    // whether the enrollment toggle is rendered at all.
    isLoadingEntitlement() {
      return this.showPaidExperience && this.$apollo.queries.entitlement.loading;
    },
    isLoadingProvisionStatus() {
      return this.$apollo.queries.secretManagerStatus?.loading ?? false;
    },
    isLoadingOpenbaoHealth() {
      return this.$apollo.queries.isOpenbaoHealthy.loading;
    },
    isProvisioning() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_PROVISIONING;
    },
    isDeprovisioning() {
      return this.secretManagerStatus === SECRET_MANAGER_STATUS_DEPROVISIONING;
    },
    isToggleDisabled() {
      return (
        !this.isOpenbaoHealthy ||
        this.isToggleLoading ||
        this.hasError ||
        !this.canManageSecretsManager ||
        this.isEnrollableAndNotEnrolled
      );
    },
    isToggleLoading() {
      return this.isLoadingProvisionStatus || this.isProvisioning || this.isDeprovisioning;
    },
    hasError() {
      return this.errorMessage.length > 0;
    },
    provisionedMessage() {
      return PROVISIONED_MESSAGES[this.context];
    },
    deprovisionedMessage() {
      return DEPROVISIONED_MESSAGES[this.context];
    },
    descriptionMessage() {
      return DESCRIPTION_MESSAGES[this.context];
    },
    provisioningToggleLabel() {
      if (this.isNamespaceEnrollable) {
        return s__('SecretsManagerPermissions|Enable GitLab Secrets Manager for this group');
      }

      return s__('SecretsManagerPermissions|GitLab Secrets Manager');
    },
    showPaidExperience() {
      return this.glFeatures.secretsManagerPaidExperience;
    },
    // Paid experience for a subgroup/project shows its own title in place of the
    // (hidden) provisioning toggle. Inside the standalone Secure block the block
    // supplies that heading, so the inline one is suppressed.
    showNonTlgTitle() {
      return !this.isNamespaceEnrollable && !this.hideInlineText;
    },
    // In the Secure block the block heading/description own the naming. A
    // non-enrollable (self-managed) beta toggle would otherwise duplicate them;
    // the enrollable (SaaS) case keeps its label as the second toggle's caption.
    showBetaInlineText() {
      return !this.hideInlineText || this.isNamespaceEnrollable;
    },
    showPermissionsTable() {
      if (!this.isOpenbaoHealthy) {
        return false;
      }

      // isEnrolled is only fetched for enrollable namespaces (SaaS top-level
      // groups), so gate on isEnrollableAndNotEnrolled rather than isEnrolled
      // to keep the table visible for subgroups, projects, and self-managed.
      return this.isActive && !this.isEnrollableAndNotEnrolled;
    },
    showSettings() {
      // always show for the beta experience
      if (!this.showPaidExperience) {
        return true;
      }

      // only show for paid experience once the enrollment toggle is actionable
      // (trial or paid add-on selected) OR if subgroup/project has provisioned
      // the secrets manager from the secrets manager page
      return hasSelectedTrialOrPaidAddOn(this.entitlement) || this.isActive;
    },
  },
  apollo: {
    entitlement: {
      query: getEntitlementQuery,
      context: { featureCategory: 'secrets_management' },
      skip() {
        return !this.topLevelGroupFullPath;
      },
      variables() {
        return {
          fullPath: this.topLevelGroupFullPath,
        };
      },
      update(data) {
        return data.group?.secretsManagerEntitlement;
      },
      error() {
        this.errorMessage = s__(
          'SecretsManagerEntitlement|An error occurred while fetching the secrets manager entitlement state. Please refresh the page.',
        );
      },
    },
    isOpenbaoHealthy: {
      query: getOpenbaoHealthQuery,
      context: { featureCategory: 'secrets_management' },
      update(data) {
        return data.openbaoHealth;
      },
      error() {
        this.isOpenbaoHealthy = false;
      },
    },
    isEnrolled: {
      query: getEnrollment,
      context: { featureCategory: 'secrets_management' },
      skip() {
        return !this.isNamespaceEnrollable;
      },
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        // An explicit opt-out resolves to null on the backend, so it reads the
        // same as never enrolled here.
        const enrolled = Boolean(data.namespaceSecretsManagerEnrollment);

        // after enrolling and refetching the status, fetch provisioning status
        // since the query may have been skipped before
        if (enrolled) {
          this.$apollo.queries.secretManagerStatus.refetch();
        }

        return enrolled;
      },
      error() {
        this.hasEnrollmentQueryError = true;
        this.errorMessage = s__(
          'SecretsManagerPermissions|An error occurred while fetching the secrets manager enrollment status. Please refresh the page.',
        );
      },
    },
    secretManagerStatus: {
      query() {
        return this.contextConfig.getStatus.query;
      },
      context: { featureCategory: 'secrets_management' },
      skip() {
        return this.isEnrollableAndNotEnrolled;
      },
      variables() {
        return {
          fullPath: this.fullPath,
        };
      },
      update(data) {
        const { secretsManager } = data;
        const newStatus = secretsManager?.status || SECRET_MANAGER_STATUS_INACTIVE;

        if (this.isEnablingSecretsManager && newStatus === SECRET_MANAGER_STATUS_ACTIVE) {
          this.$apollo.queries.secretManagerStatus.stopPolling();
          this.$toast.show(this.provisionedMessage);
        }

        if (this.isDisablingSecretsManager && newStatus === SECRET_MANAGER_STATUS_INACTIVE) {
          this.$apollo.queries.secretManagerStatus.stopPolling();
          this.$toast.show(this.deprovisionedMessage);
        }

        if (
          newStatus === SECRET_MANAGER_STATUS_ACTIVE ||
          newStatus === SECRET_MANAGER_STATUS_INACTIVE
        ) {
          this.$apollo.queries.secretManagerStatus.stopPolling();
        }

        return newStatus;
      },
      error(e) {
        this.$apollo.queries.secretManagerStatus.stopPolling(POLL_INTERVAL);
        this.errorMessage =
          e.graphQLErrors?.[0]?.message ||
          s__(
            'SecretsManagerPermissions|An error occurred while fetching the secrets manager status.',
          );

        if (this.isEnablingSecretsManager) {
          this.secretManagerStatus = SECRET_MANAGER_STATUS_INACTIVE;
        }
      },
      pollInterval: POLL_INTERVAL,
    },
  },
  methods: {
    async enableSecretsManager() {
      this.errorMessage = '';
      try {
        const { data } = await this.$apollo.mutate({
          mutation: this.contextConfig.enable.mutation,
          variables: { fullPath: this.fullPath },
          context: { featureCategory: 'secrets_management' },
        });

        const result = this.contextConfig.enable.lookup(data);
        const { secretsManager, errors } = result;

        if (errors.length > 0) {
          throw new Error(errors[0]);
        }

        this.secretManagerStatus = secretsManager?.status || SECRET_MANAGER_STATUS_INACTIVE;
        this.$apollo.queries.secretManagerStatus.startPolling(POLL_INTERVAL);
      } catch (error) {
        this.errorMessage =
          error?.message ||
          s__('SecretsManagerPermissions|An error occurred while enabling the secrets manager.');
      }
    },
    async disableSecretsManager() {
      this.errorMessage = '';
      try {
        const { data } = await this.$apollo.mutate({
          mutation: this.contextConfig.disable.mutation,
          variables: { fullPath: this.fullPath },
          context: { featureCategory: 'secrets_management' },
        });

        const result = this.contextConfig.disable.lookup(data);
        const { secretsManager, errors } = result;

        if (errors.length > 0) {
          throw new Error(errors[0]);
        }

        this.secretManagerStatus = secretsManager?.status || SECRET_MANAGER_STATUS_INACTIVE;
        this.$apollo.queries.secretManagerStatus.startPolling(POLL_INTERVAL);
      } catch (error) {
        this.errorMessage =
          error?.message ||
          s__('SecretsManagerPermissions|An error occurred while disabling the secrets manager.');
      }
    },
    fetchEnrollmentStatus() {
      this.$apollo.queries.isEnrolled.refetch();
    },
    onToggleSecretManager() {
      if (this.isInactive) {
        this.action = ACTION_ENABLE_SECRET_MANAGER;
        this.enableSecretsManager();
      } else if (this.isActive) {
        this.action = ACTION_DISABLE_SECRET_MANAGER;
        this.disableSecretsManager();
      }
    },
  },
  LEARN_MORE_LINK: helpPagePath('ci/secrets/secrets_manager/_index'),
};
</script>

<template>
  <gl-skeleton-loader
    v-if="isLoadingOpenbaoHealth || isLoadingEnrollment || isLoadingEntitlement"
  />
  <div v-else-if="showSettings" data-testid="secret-manager">
    <saas-enrollment-toggle
      v-if="isNamespaceEnrollable"
      :can-manage-enrollment="canEnrollNamespace"
      :full-path="fullPath"
      :is-enrolled="isEnrolled"
      :disabled="isBlockedByEntitlement"
      :has-enrollment-query-error="hasEnrollmentQueryError"
      :hide-inline-text="hideInlineText"
      @toggled="fetchEnrollmentStatus"
    />
    <!-- Show provisioning toggle only for the beta experience -->
    <template v-if="!showPaidExperience">
      <template v-if="showBetaInlineText">
        <label
          for="provisioning-toggle"
          data-testid="provisioning-toggle-label"
          class="gl-mb-1"
          :class="{ 'gl-mb-2 gl-ml-6 gl-mt-4': isNamespaceEnrollable }"
        >
          {{ provisioningToggleLabel }}
        </label>
        <p
          class="gl-mb-2 gl-text-subtle"
          data-testid="provisioning-toggle-description"
          :class="{ 'gl-ml-6': isNamespaceEnrollable }"
        >
          {{ descriptionMessage }}
          <gl-link v-if="!isNamespaceEnrollable" :href="$options.LEARN_MORE_LINK">
            {{ __('Learn more.') }}
          </gl-link>
        </p>
      </template>
      <gl-toggle
        id="provisioning-toggle"
        :value="isActive"
        :label="provisioningToggleLabel"
        :disabled="isToggleDisabled"
        :is-loading="isToggleLoading"
        :class="{ 'gl-ml-6': isNamespaceEnrollable }"
        label-position="hidden"
        name="secret_manager_enabled"
        data-testid="secret-manager-toggle"
        @change="onToggleSecretManager"
      />
    </template>
    <!-- Since we hide the provisioning toggle for the paid experience -->
    <!-- we need to show the title text for subgroups and projects (not as a label) -->
    <template v-else-if="showNonTlgTitle">
      <p data-testid="non-tlg-settings-title" class="gl-mb-1 gl-text-base gl-font-bold">
        {{ provisioningToggleLabel }}
      </p>
      <p class="gl-mb-2 gl-text-subtle" data-testid="non-tlg-settings-description">
        {{ descriptionMessage }}
        <gl-link v-if="!isNamespaceEnrollable" :href="$options.LEARN_MORE_LINK">
          {{ __('Learn more.') }}
        </gl-link>
      </p>
    </template>
    <p v-if="hasError" class="gl-mt-2 gl-text-danger" data-testid="secret-manager-error">
      {{ errorMessage }}
    </p>
    <secrets-manager-billing-alert :entitlement="entitlement" />
    <permissions-settings
      v-if="showPermissionsTable"
      :can-manage-secrets-manager="canManageSecretsManager"
      :full-path="fullPath"
      :context="context"
    />
    <gl-alert
      v-if="!isOpenbaoHealthy"
      variant="danger"
      :dismissible="false"
      class="gl-mb-4 gl-mt-4"
      data-testid="openbao-unhealthy-alert"
    >
      {{
        s__(
          'SecretsManager|Failed to connect with OpenBao. Secrets are currently unavailable, please try again later.',
        )
      }}
    </gl-alert>
  </div>
</template>
