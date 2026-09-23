<script>
import { GlAlert, GlButton, GlLink, GlPopover } from '@gitlab/ui';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { logError } from '~/lib/logger';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import SecretsManagerBillingAlert from 'ee/ci/secrets/components/secrets_manager_billing_alert.vue';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';
import { isProvisioningBlockedByEntitlement } from 'ee/ci/secrets/utils';
import {
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
  CREDIT_CONSUMPTION_ALERT,
} from 'ee/ci/secrets/constants';
import getInstanceEntitlementQuery from '../graphql/queries/get_instance_secrets_manager_entitlement.query.graphql';
import getInstanceSecretsManagerEnrollmentQuery from '../graphql/queries/get_instance_secrets_manager_enrollment.query.graphql';
import enableInstanceSecretsManagerAddOnMutation from '../graphql/mutations/enable_instance_secrets_manager_add_on.mutation.graphql';
import startInstanceSecretsManagerTrialMutation from '../graphql/mutations/start_instance_secrets_manager_trial.mutation.graphql';
import SecretsManagerInstanceEnrollmentToggle from './secrets_manager_instance_enrollment_toggle.vue';

export default {
  name: 'SecretsManagerInstanceSettings',
  components: {
    EnableAddOnModal,
    GlAlert,
    GlButton,
    GlLink,
    GlPopover,
    SecretsManagerBillingAlert,
    SecretsManagerInstanceEnrollmentToggle,
    StartTrialModal,
  },
  i18n: {
    loadError: s__('SecretsManager|Failed to load Secrets Manager enrollment state.'),
    enableAddOnError: s__(
      'SecretsManager|The GitLab Secrets Manager add-on could not be enabled. Please try again.',
    ),
  },
  creditConsumptionAlert: CREDIT_CONSUMPTION_ALERT,
  SECRETS_MANAGER_TRIAL_DOCS_LINK: helpPagePath('ci/secrets/secrets_manager/credit_usage'),
  mixins: [glFeatureFlagsMixin()],
  data() {
    return {
      entitlement: null,
      errorMessage: '',
      isEnablingAddOn: false,
      isEnrolled: false,
      isStartingTrial: false,
      showEnableAddOnModal: false,
      showEnrollSuccessAlert: false,
      showStartTrialModal: false,
      showTrialEnrollmentWarning: false,
    };
  },
  apollo: {
    entitlement: {
      query: getInstanceEntitlementQuery,
      context: { featureCategory: 'secrets_management' },
      skip() {
        return !this.showPaidExperience;
      },
      update(data) {
        return data.secretsManagerInstanceEntitlement;
      },
      error(error) {
        this.reportError(error);
      },
    },
    isEnrolled: {
      query: getInstanceSecretsManagerEnrollmentQuery,
      context: { featureCategory: 'secrets_management' },
      fetchPolicy: 'network-only',
      update(data) {
        return Boolean(data?.instanceSecretsManagerEnrollment?.enrolled);
      },
      error(error) {
        this.reportError(error);
      },
    },
  },
  computed: {
    isBlockedByEntitlement() {
      return this.showPaidExperience && isProvisioningBlockedByEntitlement(this.entitlement);
    },
    isEnrollmentLoading() {
      return this.$apollo.queries.isEnrolled.loading;
    },
    isOfflineLicense() {
      return this.entitlement?.offlineLicense;
    },
    showPaidExperience() {
      return this.glFeatures.secretsManagerPaidExperience;
    },
    showTrialNote() {
      return !this.isOfflineLicense;
    },
    // Trials require CDot connectivity, so air-gapped instances keep the toggle.
    showStartTrialButton() {
      return (
        this.showPaidExperience &&
        !this.isOfflineLicense &&
        this.entitlement?.state === ENTITLEMENT_STATE_TRIAL_ELIGIBLE
      );
    },
    onDemandEnabled() {
      return Boolean(this.entitlement?.onDemandEnabled);
    },
  },
  methods: {
    reportError(error, message = this.$options.i18n.loadError) {
      this.errorMessage = message;

      logError(message, error);
      Sentry.captureException(error);
    },
    onToggled(isEnrolled) {
      this.isEnrolled = isEnrolled;
      this.showEnrollSuccessAlert = isEnrolled;
      this.showTrialEnrollmentWarning = false;
    },
    async startTrial() {
      this.showStartTrialModal = false;
      this.isStartingTrial = true;
      this.errorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: startInstanceSecretsManagerTrialMutation,
          context: { featureCategory: 'secrets_management' },
        });
        const { entitlement, errors = [] } = data?.secretsManagerInstanceStartTrial ?? {};

        // The backend auto-enrolls the instance after starting the trial. A
        // non-null entitlement means the trial started even when enrollment
        // failed; the toggle is the retry path for enrollment, so warn without
        // discarding the trial.
        if (!entitlement && errors.length) {
          throw new Error(errors.join(', '));
        }

        // A null entitlement with no errors means the trial started and the
        // instance is enrolled, but the post-trial entitlement lookup failed
        // on the backend; refetch instead of discarding the success.
        if (!entitlement) {
          this.isEnrolled = true;
          this.showEnrollSuccessAlert = true;
          await this.$apollo.queries.entitlement.refetch();
          return;
        }

        this.entitlement = entitlement;
        this.isEnrolled = errors.length === 0;
        this.showEnrollSuccessAlert = this.isEnrolled;
        this.showTrialEnrollmentWarning = !this.isEnrolled;
      } catch (error) {
        this.reportError(
          error,
          s__(
            'SecretsManager|The GitLab Secrets Manager trial could not be started. Please try again.',
          ),
        );
      } finally {
        this.isStartingTrial = false;
      }
    },
    async enableAddOn() {
      this.showEnableAddOnModal = false;
      this.isEnablingAddOn = true;
      this.errorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: enableInstanceSecretsManagerAddOnMutation,
          context: { featureCategory: 'secrets_management' },
        });
        const { entitlement, errors = [] } = data?.secretsManagerInstanceEnableAddOn ?? {};

        // All-or-nothing: the backend enrolls and stamps the add-on intent
        // locally with a revert guard, so unlike the trial mutation there
        // is no partial-success shape to handle.
        if (!entitlement) {
          const message = errors[0] || this.$options.i18n.enableAddOnError;
          this.reportError(new Error(message), message);
          return;
        }

        this.entitlement = entitlement;
        this.isEnrolled = true;
        this.showEnrollSuccessAlert = true;
      } catch (error) {
        this.reportError(error, this.$options.i18n.enableAddOnError);
      } finally {
        this.isEnablingAddOn = false;
      }
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
      data-testid="settings-error-alert"
      @dismiss="errorMessage = ''"
    >
      {{ errorMessage }}
    </gl-alert>
    <gl-alert
      v-if="showTrialEnrollmentWarning"
      class="gl-mb-4"
      variant="warning"
      data-testid="trial-enrollment-warning-alert"
      @dismiss="showTrialEnrollmentWarning = false"
    >
      {{
        s__(
          'SecretsManager|The trial has started, but the instance failed to enable the secrets manager. Please try again with the toggle below.',
        )
      }}
    </gl-alert>
    <gl-alert
      v-if="showEnrollSuccessAlert"
      class="gl-mb-4"
      variant="success"
      data-testid="enroll-success-alert"
      @dismiss="showEnrollSuccessAlert = false"
    >
      {{
        s__(
          'SecretsManager|The GitLab Secrets Manager has been enabled for all groups and projects in this instance. Visit any group or project to create secrets.',
        )
      }}
    </gl-alert>
    <template v-if="showStartTrialButton">
      <div class="gl-flex gl-items-center gl-gap-4">
        <gl-button
          ref="enableAddOnButton"
          variant="confirm"
          category="primary"
          :loading="isEnablingAddOn"
          :disabled="isStartingTrial"
          data-testid="instance-enable-add-on-button"
          @click="showEnableAddOnModal = true"
        >
          {{ s__('SecretsManager|Enable with GitLab Credits') }}
        </gl-button>
        <gl-button
          ref="startTrialButton"
          variant="confirm"
          category="secondary"
          :loading="isStartingTrial"
          :disabled="isEnablingAddOn"
          data-testid="instance-start-trial-button"
          @click="showStartTrialModal = true"
        >
          {{ __('Start 30-day trial') }}
        </gl-button>
        <gl-link
          :href="$options.SECRETS_MANAGER_TRIAL_DOCS_LINK"
          target="_blank"
          rel="noopener noreferrer"
          data-testid="learn-more-trial-link"
        >
          {{ s__('SecretsManager|Learn more about the trial') }}
        </gl-link>
      </div>
      <gl-popover
        :target="() => $refs.enableAddOnButton"
        :show="isEnablingAddOn"
        :title="s__('SecretsManager|Enabling GitLab Secrets Manager')"
        placement="bottom"
        triggers="manual"
      >
        {{
          s__('SecretsManager|Do not close this page until Secrets Manager is finished setting up.')
        }}
      </gl-popover>
      <gl-popover
        :target="() => $refs.startTrialButton"
        :show="isStartingTrial"
        :title="s__('SecretsManager|Enabling GitLab Secrets Manager trial')"
        placement="bottom"
        triggers="manual"
      >
        {{
          s__('SecretsManager|Do not close this page until Secrets Manager is finished setting up.')
        }}
      </gl-popover>
      <enable-add-on-modal
        :visible="showEnableAddOnModal"
        :on-demand-enabled="onDemandEnabled"
        @enable="enableAddOn"
        @hide="showEnableAddOnModal = false"
      />
      <start-trial-modal
        :visible="showStartTrialModal"
        @start-trial="startTrial"
        @hide="showStartTrialModal = false"
      />
    </template>
    <secrets-manager-instance-enrollment-toggle
      v-else
      :is-enrolled="isEnrolled"
      :disabled="isBlockedByEntitlement"
      :loading="isEnrollmentLoading"
      :show-trial-note="showTrialNote"
      :is-offline-license="isOfflineLicense"
      @toggled="onToggled"
    />
    <!-- only show for beta users -->
    <secrets-manager-billing-alert v-if="!showPaidExperience" />
    <!-- only show for cloud license (not air-gapped) -->
    <gl-alert
      v-else-if="entitlement && !isOfflineLicense"
      class="gl-mt-5"
      variant="info"
      :dismissible="false"
      data-testid="credit-consumption-alert"
    >
      {{ $options.creditConsumptionAlert.description }}
      <gl-link class="gl-inline-block" :href="$options.creditConsumptionAlert.link" target="_blank">
        {{ $options.creditConsumptionAlert.linkText }}
      </gl-link>
    </gl-alert>
  </div>
</template>
